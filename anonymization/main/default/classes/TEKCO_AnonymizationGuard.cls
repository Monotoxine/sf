/**
 * @description 
 */
public inherited sharing class TEKCO_AnonymizationGuard {

    private static final String ANONYMIZE_PERMISSION = 'TEKCO_AnonymizeData';
    private static final Integer MAX_NAMED_CONFIGS = 3;
    private static final String KEY_SEPARATOR = '\u0001';

    public class RefusalException extends Exception {}

    /**
     * The exception a refusal is thrown as. The interface needs an AuraHandledException to show
     * the message, but a scheduled job cannot throw one at all: the platform fails the job on the
     * spot, before the scheduler can catch it and log the refusal. So a scheduled job gets a
     * plain RefusalException instead. getMessage() of an AuraHandledException returns
     * "Script-thrown exception" unless setMessage is called.
     */
    public static Exception rejection(String message) {
        if (Request.getCurrent().getQuiddity() == Quiddity.SCHEDULED) {
            return new RefusalException(message);
        }
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    public static void assertCanAnonymize() {
        if (!FeatureManagement.checkPermission(ANONYMIZE_PERMISSION)) {
            throw rejection(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }
    }

    public static void assertNoRunInProgress() {
        List<TEKCO_AnonymizationAuditLog__c> running = [
            SELECT Id, Name, TEKCO_JobId__c, TEKCO_StartTime__c, TEKCO_TriggeredBy__r.Name
            FROM TEKCO_AnonymizationAuditLog__c
            WHERE TEKCO_Status__c = 'Running'
            ORDER BY TEKCO_StartTime__c DESC
            LIMIT 50
        ];
        if (running.isEmpty()) return;

        Map<Id, AsyncApexJob> jobsById = loadJobs(running);
        Datetime staleBefore = Datetime.now().addMinutes(-UNSTARTED_LAUNCH_GRACE_MINUTES);

        for (TEKCO_AnonymizationAuditLog__c log : running) {
            Id jobId = asJobId(log.TEKCO_JobId__c);

            if (jobId == null) {
                if (log.TEKCO_StartTime__c != null && log.TEKCO_StartTime__c > staleBefore) {
                    throw refusal(log);
                }
                continue;
            }

            AsyncApexJob job = jobsById.get(jobId);
            if (job != null && LIVE_JOB_STATUSES.contains(job.Status)) {
                throw refusal(log);
            }
        }
    }

    private static final Integer UNSTARTED_LAUNCH_GRACE_MINUTES = 5;

    private static final Set<String> LIVE_JOB_STATUSES = new Set<String>{
        'Holding', 'Queued', 'Preparing', 'Processing'
    };

    private static Exception refusal(TEKCO_AnonymizationAuditLog__c log) {
        String who = log.TEKCO_TriggeredBy__r != null ? log.TEKCO_TriggeredBy__r.Name : 'another user';
        return rejection(
            'An anonymization run is already in progress (' + log.Name + ', started by ' + who
            + ' on ' + String.valueOf(log.TEKCO_StartTime__c) + '). Two runs at once would leave '
            + 'the automation bypass in an inconsistent state. Wait for it to finish.'
        );
    }

    private static Map<Id, AsyncApexJob> loadJobs(List<TEKCO_AnonymizationAuditLog__c> logs) {
        Set<Id> jobIds = new Set<Id>();
        for (TEKCO_AnonymizationAuditLog__c log : logs) {
            Id jobId = asJobId(log.TEKCO_JobId__c);
            if (jobId != null) jobIds.add(jobId);
        }
        if (jobIds.isEmpty()) return new Map<Id, AsyncApexJob>();
        return new Map<Id, AsyncApexJob>([
            SELECT Id, Status FROM AsyncApexJob WHERE Id IN :jobIds
        ]);
    }

    private static Id asJobId(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            return Id.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    public static String requireConfiguredObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw rejection('Object API name is required.');
        }
        String canonical =
            TEKCO_AnonymizationConfigSelector.configuredObjectsByLower().get(objectApiName.toLowerCase());
        if (canonical == null) {
            throw rejection(
                'Object is not configured for anonymization: ' + objectApiName
            );
        }
        return canonical;
    }

    public static String requireFieldOnObject(String objectApiName, String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            throw rejection('Field API name is required.');
        }
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, fieldApiName)) {
            throw rejection(
                'Field does not exist on ' + objectApiName + ': ' + fieldApiName
            );
        }
        return fieldApiName;
    }

    public static List<String> validatePatternTypes(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> warnings = new List<String>();
        if (configs == null || configs.isEmpty()) return warnings;

        Set<String> handledElsewhere = new Set<String>{
            'DELETE_CONTENT_DOCUMENT', 'EMAIL_MESSAGE_LOREM', 'KEEP'
        };
        Map<String, TEKCO_AnonymizationPattern__mdt> active =
            TEKCO_AnonymizationConfigSelector.buildPatternMap();

        Set<String> reported = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            String patternType = fc.TEKCO_PatternType__c;
            if (String.isBlank(patternType) || handledElsewhere.contains(patternType)) continue;
            TEKCO_AnonymizationPattern__mdt activePattern = active.get(patternType);
            if (patternType.startsWith('EMAIL_PLUS_')
                    && activePattern != null
                    && String.isBlank(activePattern.TEKCO_BaseEmail__c)
                    && reported.add(patternType + '#baseEmail')) {
                warnings.add(TEKCO_AnonymizationRunContext.cap(
                    'Config warning: pattern "' + patternType + '" has no TEKCO_BaseEmail__c. '
                    + 'It will append to the existing value instead of replacing it, so running '
                    + 'twice produces base+ID+ID@... and eventually overflows the field.'
                ));
            }

            if (active.containsKey(patternType)) continue;
            if (!reported.add(patternType)) continue;
            warnings.add(TEKCO_AnonymizationRunContext.cap(
                'Config warning: pattern type "' + patternType + '" has no active '
                + 'TEKCO_AnonymizationPattern__mdt record. Fields using it will be left unchanged '
                + '(e.g. ' + fc.TEKCO_ObjectApiName__c + '.' + fc.TEKCO_FieldApiName__c + ').'
            ));
        }
        return warnings;
    }

    public static List<String> validateAdditionalFilters(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> warnings = new List<String>();
        if (configs == null || configs.isEmpty()) return warnings;
        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObjectAndFilter =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            if (config == null || String.isBlank(config.TEKCO_AdditionalFilter__c)) continue;
            if (String.isBlank(config.TEKCO_ObjectApiName__c)) continue;
            String key = config.TEKCO_ObjectApiName__c + KEY_SEPARATOR
                + config.TEKCO_AdditionalFilter__c;
            if (!configsByObjectAndFilter.containsKey(key)) {
                configsByObjectAndFilter.put(
                    key, new List<TEKCO_AnonymizationFieldConfig__mdt>()
                );
            }
            configsByObjectAndFilter.get(key).add(config);
        }

        for (List<TEKCO_AnonymizationFieldConfig__mdt> sharing : configsByObjectAndFilter.values()) {
            String objectApiName = sharing[0].TEKCO_ObjectApiName__c;
            String filter        = sharing[0].TEKCO_AdditionalFilter__c;
            try {
                Database.query('SELECT Id FROM ' + objectApiName + ' WHERE ' + filter + ' LIMIT 1');
            } catch (Exception e) {
                warnings.add(TEKCO_AnonymizationRunContext.cap(
                    'Config warning: the additional filter of ' + describe(sharing)
                    + ' is not a valid condition on ' + objectApiName
                    + ', so that rule will be skipped: ' + e.getMessage()
                ));
            }
        }
        return warnings;
    }

    /**
     * The By ID tab reaches a child object through TEKCO_ParentLookupFieldApiName__c. A lookup
     * that does not exist on the child, or does not lead to the parent object, resolves no child
     * at all, and the run reports success without touching them.
     */
    @TestVisible
    private static List<String> validateParentLookups(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> warnings = new List<String>();
        if (configs == null || configs.isEmpty()) return warnings;

        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByLookup =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            if (config == null || String.isBlank(config.TEKCO_ObjectApiName__c)) continue;
            Boolean hasParent = String.isNotBlank(config.TEKCO_ParentObjectApiName__c);
            Boolean hasLookup = String.isNotBlank(config.TEKCO_ParentLookupFieldApiName__c);
            if (!hasParent && !hasLookup) continue;
            if (hasParent != hasLookup) {
                warnings.add(TEKCO_AnonymizationRunContext.cap(
                    'Config warning: ' + describe(new List<TEKCO_AnonymizationFieldConfig__mdt>{ config })
                    + ' sets only one of TEKCO_ParentObjectApiName__c and '
                    + 'TEKCO_ParentLookupFieldApiName__c, so By ID never reaches its records.'
                ));
                continue;
            }
            String key = config.TEKCO_ObjectApiName__c + KEY_SEPARATOR
                + config.TEKCO_ParentLookupFieldApiName__c + KEY_SEPARATOR
                + config.TEKCO_ParentObjectApiName__c;
            if (!configsByLookup.containsKey(key)) {
                configsByLookup.put(key, new List<TEKCO_AnonymizationFieldConfig__mdt>());
            }
            configsByLookup.get(key).add(config);
        }

        for (List<TEKCO_AnonymizationFieldConfig__mdt> sharing : configsByLookup.values()) {
            String objectApiName = sharing[0].TEKCO_ObjectApiName__c;
            String lookup        = sharing[0].TEKCO_ParentLookupFieldApiName__c;
            String parent        = sharing[0].TEKCO_ParentObjectApiName__c;
            if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) continue;

            String problem;
            if (!TEKCO_AnonymizationOrgConfigService.hasObject(parent)) {
                problem = 'its parent object ' + parent + ' does not exist';
            } else {
                try {
                    Database.query('SELECT Id FROM ' + objectApiName + ' WHERE ' + lookup + ' = null LIMIT 0');
                    if (!leadsTo(objectApiName, lookup, parent)) {
                        problem = objectApiName + '.' + lookup + ' does not point to ' + parent;
                    }
                } catch (Exception e) {
                    problem = objectApiName + '.' + lookup + ' is not a valid lookup: ' + e.getMessage();
                }
            }
            if (problem != null) {
                warnings.add(TEKCO_AnonymizationRunContext.cap(
                    'Config warning: the parent lookup of ' + describe(sharing) + ' is broken, '
                    + 'so By ID never reaches its ' + objectApiName + ' records: ' + problem
                ));
            }
        }
        return warnings;
    }

    // Follows a lookup path such as "AccountId" or "Parent.AccountId" through the describe and
    // tells whether its last field references the parent object.
    private static Boolean leadsTo(String objectApiName, String path, String parentObject) {
        Set<String> currentObjects = new Set<String>{ objectApiName };
        List<String> segments = path.split('\\.');
        for (Integer i = 0; i < segments.size(); i++) {
            Boolean last = i == segments.size() - 1;
            Set<String> next = new Set<String>();
            for (String obj : currentObjects) {
                Map<String, Schema.SObjectField> fields = TEKCO_AnonymizationOrgConfigService.getFieldMap(obj);
                if (fields == null) continue;
                for (Schema.SObjectField f : fields.values()) {
                    Schema.DescribeFieldResult d = f.getDescribe();
                    Boolean matches = last
                        ? d.getName().equalsIgnoreCase(segments[i])
                        : segments[i].equalsIgnoreCase(d.getRelationshipName());
                    if (!matches) continue;
                    for (Schema.SObjectType target : d.getReferenceTo()) {
                        next.add(target.getDescribe().getName());
                    }
                }
            }
            if (last) {
                for (String target : next) {
                    if (target.equalsIgnoreCase(parentObject)) return true;
                }
                return false;
            }
            currentObjects = next;
        }
        return false;
    }

    private static String describe(List<TEKCO_AnonymizationFieldConfig__mdt> configs) {
        List<String> names = new List<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            if (names.size() == MAX_NAMED_CONFIGS) break;
            names.add(
                String.isNotBlank(config.MasterLabel) ? config.MasterLabel : config.DeveloperName
            );
        }
        names.sort();
        String described = String.join(names, ', ');
        Integer remaining = configs.size() - names.size();
        return remaining > 0 ? described + ' (+' + remaining + ')' : described;
    }

    public static List<String> validateConfiguration() {
        List<String> findings = new List<String>();

        List<TEKCO_AnonymizationFieldConfig__mdt> configs = [
            SELECT DeveloperName, MasterLabel, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_RecordTypeDeveloperName__c,
                   TEKCO_AdditionalFilter__c, TEKCO_ParentObjectApiName__c,
                   TEKCO_ParentLookupFieldApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
        ];

        List<TEKCO_AnonymizationFieldConfig__mdt> filterConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Set<String> missingObjects = new Set<String>();

        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            String objectApiName = config.TEKCO_ObjectApiName__c;
            if (String.isBlank(objectApiName)) {
                findings.add('Config "' + config.DeveloperName + '" names no object.');
                continue;
            }

            if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
                if (missingObjects.add(objectApiName)) {
                    findings.add(
                        'Object "' + objectApiName + '" does not exist in this org — every config '
                        + 'on it is silently skipped (first one: ' + config.DeveloperName + ').'
                    );
                }
                continue;
            }

            String fieldApiName = config.TEKCO_FieldApiName__c;
            if (String.isNotBlank(fieldApiName)
                    && !TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, fieldApiName)) {
                findings.add(
                    'Field "' + objectApiName + '.' + fieldApiName + '" does not exist — config "'
                    + config.DeveloperName + '" is silently skipped.'
                );
            }

            if (String.isNotBlank(config.TEKCO_AdditionalFilter__c)) {
                filterConfigs.add(config);
            }
        }

        findings.addAll(validatePatternTypes(configs));
        findings.addAll(validateAdditionalFilters(filterConfigs));
        findings.addAll(validateFilterDiscrimination(configs));
        findings.addAll(validateParentLookups(configs));
        return findings;
    }

    @TestVisible
    private static List<String> validateFilterDiscrimination(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> findings = new List<String>();
        if (configs == null || configs.isEmpty()) return findings;

        Map<String, Map<String, Set<String>>> effectsByFilterByObject =
            new Map<String, Map<String, Set<String>>>();

        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            if (config == null || String.isBlank(config.TEKCO_AdditionalFilter__c)) continue;
            if (String.isBlank(config.TEKCO_ObjectApiName__c)) continue;

            String objectApiName = config.TEKCO_ObjectApiName__c;
            if (!effectsByFilterByObject.containsKey(objectApiName)) {
                effectsByFilterByObject.put(objectApiName, new Map<String, Set<String>>());
            }
            Map<String, Set<String>> byFilter = effectsByFilterByObject.get(objectApiName);
            String filter = config.TEKCO_AdditionalFilter__c;
            if (!byFilter.containsKey(filter)) byFilter.put(filter, new Set<String>());
            byFilter.get(filter).add(
                config.TEKCO_FieldApiName__c + ':' + config.TEKCO_PatternType__c
            );
        }

        for (String objectApiName : effectsByFilterByObject.keySet()) {
            Map<String, Set<String>> byFilter = effectsByFilterByObject.get(objectApiName);
            if (byFilter.size() < 2) continue;

            Set<String> reference = null;
            for (Set<String> effects : byFilter.values()) {
                if (reference == null) {
                    reference = effects;
                } else if (!reference.containsAll(effects) || !effects.containsAll(reference)) {
                    findings.add(TEKCO_AnonymizationRunContext.cap(
                        'Config warning: ' + objectApiName + ' carries ' + byFilter.size()
                        + ' different additional filters whose rules do different things. The '
                        + 'engine reads their union and cannot tell, record by record, which '
                        + 'filter brought a record in, so every rule is applied to all of them. '
                        + 'Use record types instead, or give the rules the same effect.'
                    ));
                    break;
                }
            }
        }
        return findings;
    }

    public static Boolean assertSandboxOrClose(
        Id auditLogId,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot
    ) {
        try {
            TEKCO_AnonymizationOrgConfigService.assertIsSandbox();
            return true;
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Bypass restore failed; flags may remain enabled: ' + ex.getMessage()
                );
            }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, 0, 0, 0, 0, new List<String>(), e.getMessage()
            );
            return false;
        }
    }
}
