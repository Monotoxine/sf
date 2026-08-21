/**
 * @description Everything the tool refuses, in one place.
 *
 *              Five gates, all of them the last line of defence for an admin tool that reads and
 *              destroys PII across arbitrary objects:
 *                - the custom permission, checked on every @AuraEnabled entry point
 *                - object and field names, before they are concatenated into dynamic SOQL
 *                - pattern types that resolve to nothing, surfaced at launch instead of silently
 *                  skipping fields at execute() time
 *                - the sandbox check, in the form a batch start() can survive
 *
 *              Split out of the former TEKCO_AnonymizationBatchUtils. Its name said "batch", but
 *              these gates are called mostly from the controllers — which is precisely how a
 *              grab-bag hides what it does.
 */
public inherited sharing class TEKCO_AnonymizationGuard {

    private static final String ANONYMIZE_PERMISSION = 'TEKCO_AnonymizeData';

    /**
     * Gate for every @AuraEnabled entry point. The anonymization UI reads and destroys PII
     * across arbitrary objects, so read-only endpoints are gated too — not just the ones
     * that launch a batch.
     */
    public static void assertCanAnonymize() {
        if (!FeatureManagement.checkPermission(ANONYMIZE_PERMISSION)) {
            throw new AuraHandledException(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }
    }

    /**
     * A launch is refused while another run is genuinely in flight.
     *
     * The bypass cannot survive two concurrent runs. activate() snapshots the CURRENT state of
     * the hierarchy setting as the "original" one: a second run started while the first is up
     * records `true` as the original and, when it ends, restores `true` — leaving the org's
     * automation disabled for that user with nothing left to switch it back. The other ordering
     * is just as bad: the first run to finish restores `false` and the second carries on writing
     * PII with every trigger and outbound sync firing.
     *
     * Org-wide rather than per-user. The bypass itself is per-user, but two concurrent runs would
     * also fight over the org's five concurrent batch slots and could process the same records.
     */
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
                // Inserted, but the batch has not been enqueued yet — or the launch died between
                // the two. Live only if it just happened; past the grace window it is a stale log
                // and must not lock the tool out for good.
                if (log.TEKCO_StartTime__c != null && log.TEKCO_StartTime__c > staleBefore) {
                    throw refusal(log);
                }
                continue;
            }

            AsyncApexJob job = jobsById.get(jobId);
            // Job gone, Completed, Failed or Aborted: the log is stale because finish() never ran.
            if (job != null && LIVE_JOB_STATUSES.contains(job.Status)) {
                throw refusal(log);
            }
        }
    }

    /** Minutes a log with no job Id is still considered a launch in progress. */
    private static final Integer UNSTARTED_LAUNCH_GRACE_MINUTES = 5;

    private static final Set<String> LIVE_JOB_STATUSES = new Set<String>{
        'Holding', 'Queued', 'Preparing', 'Processing'
    };

    private static AuraHandledException refusal(TEKCO_AnonymizationAuditLog__c log) {
        String who = log.TEKCO_TriggeredBy__r != null ? log.TEKCO_TriggeredBy__r.Name : 'another user';
        return new AuraHandledException(
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

    /** The job Id is stored as text; anything unparseable is treated as absent. */
    private static Id asJobId(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            return Id.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Object API names reaching dynamic SOQL must be one the tool is configured for.
     * Client-supplied names are otherwise concatenated straight into a query.
     * Returns the canonical configured name, or throws.
     *
     * Note this validates against the configuration, not against the org's schema: an object
     * configured but absent from this org still passes here, and the batches guard that
     * separately with TEKCO_AnonymizationOrgConfigService.hasObject().
     */
    public static String requireConfiguredObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        String canonical =
            TEKCO_AnonymizationConfigSelector.configuredObjectsByLower().get(objectApiName.toLowerCase());
        if (canonical == null) {
            throw new AuraHandledException(
                'Object is not configured for anonymization: ' + objectApiName
            );
        }
        return canonical;
    }

    /**
     * Field API names reaching dynamic SOQL must exist on the object.
     * Returns the supplied name when valid, otherwise throws.
     */
    public static String requireFieldOnObject(String objectApiName, String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            throw new AuraHandledException('Field API name is required.');
        }
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, fieldApiName)) {
            throw new AuraHandledException(
                'Field does not exist on ' + objectApiName + ': ' + fieldApiName
            );
        }
        return fieldApiName;
    }

    /**
     * Field configs whose TEKCO_PatternType__c has no matching active
     * TEKCO_AnonymizationPattern__mdt are skipped silently by
     * TEKCO_AnonymizationExecuteService (the `pattern == null` continue) — the field is
     * never anonymized and nothing reports it. Surfaced at launch instead, as warnings
     * seeded into the audit log so the run still processes the valid configs.
     *
     * DELETE_CONTENT_DOCUMENT and EMAIL_MESSAGE_LOREM are handled by dedicated batches and
     * need no pattern record.
     */
    public static List<String> validatePatternTypes(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> warnings = new List<String>();
        if (configs == null || configs.isEmpty()) return warnings;

        // These need no pattern record. The first two are handled by dedicated batches. KEEP is
        // a deliberate no-op: with no record it is skipped before the transformation runs, which
        // leaves the value untouched — exactly what it means. Flagging it would cry wolf on the
        // very first configuration check.
        Set<String> handledElsewhere = new Set<String>{
            'DELETE_CONTENT_DOCUMENT', 'EMAIL_MESSAGE_LOREM', 'KEEP'
        };
        Map<String, TEKCO_AnonymizationPattern__mdt> active =
            TEKCO_AnonymizationConfigSelector.buildPatternMap();

        Set<String> reported = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            String patternType = fc.TEKCO_PatternType__c;
            if (String.isBlank(patternType) || handledElsewhere.contains(patternType)) continue;

            // An EMAIL_PLUS_* pattern with no base e-mail falls back to the record's own value,
            // so it appends instead of replacing: a second run yields base+ID+ID@..., a third
            // adds again, until the field length is exceeded and the DML fails. The anonymization
            // stops being idempotent, which matters on an org re-anonymized after every refresh.
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

    /**
     * Additional filters are the one string that bypasses requireConfiguredObject() and
     * requireFieldOnObject(): they come from CMDT and are concatenated straight into the scope
     * query. A malformed one already fails safely — start() catches it and skips the step — but
     * only hours into the run. Parsing it here surfaces it at launch instead.
     *
     * Takes the CONFIGS rather than a filter-per-object map, so a finding can name the record to
     * open in Setup. An object is not an address: Contact carries five configs sharing one filter
     * and User six, while Address carries two that differ — "the filter on Contact is invalid"
     * tells the reader nothing about which of the five to fix.
     *
     * One query per DISTINCT (object, filter), not per config: the fifteen configs carrying a
     * filter today collapse to five queries. Configs sharing a filter are named together on the
     * one finding.
     *
     * This does NOT catch a filter that is valid but wrong. Such a filter silently narrows the
     * scope, the run ends in Success and the PII stays. Only the scope preview shows that.
     */
    public static List<String> validateAdditionalFilters(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> warnings = new List<String>();
        if (configs == null || configs.isEmpty()) return warnings;

        // Keyed on object + filter so one query covers every config that shares the condition,
        // and so the finding can list them all.
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

    /** Names of the configs sharing one filter, at most three then a count. */
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

    /** Configs listed by name on a shared-filter finding before it turns into a count. */
    private static final Integer MAX_NAMED_CONFIGS = 3;

    /** Joins object and filter into one map key. A control character, because a filter can
     *  legitimately contain any punctuation. */
    private static final String KEY_SEPARATOR = '\u0001';

    /**
     * Everything wrong with the configuration, reported before any run rather than as lines
     * buried in a capped error list halfway through one.
     *
     * Catches what a typo produces today: an object API name that does not exist in this org is
     * merely "skipped" at batch start, and the field it was meant to protect keeps its PII with
     * no visible signal.
     */
    public static List<String> validateConfiguration() {
        List<String> findings = new List<String>();

        List<TEKCO_AnonymizationFieldConfig__mdt> configs = [
            SELECT DeveloperName, MasterLabel, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_RecordTypeDeveloperName__c,
                   TEKCO_AdditionalFilter__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
        ];

        // Filters are checked on the configs that survive the object check: querying a filter on
        // an object that does not exist here would only restate the finding above it.
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
            // A blank field name is normal for DELETE_CONTENT_DOCUMENT: that phase works on the
            // record's files, not on one of its fields.
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
        return findings;
    }

    /**
     * The one shape the engine cannot honour, reported before it is ever configured.
     *
     * A run reads an object with ONE query, whose scope is the OR of its rules' filters, then
     * applies each rule record by record. Apex can re-check a record type — it reads
     * RecordTypeId — but not a filter, which usually walks a relationship. So when an object
     * carries two different filters, every rule is applied to every record the union returned,
     * whichever filter brought it in.
     *
     * That is only observable when the rules behind the two filters do DIFFERENT things.
     * Address.Street is carried by two filters with the same field and the same pattern, so
     * applying either to either population gives the same result — no finding, and rightly so.
     * Two filters driving different fields or different patterns would silently over-apply.
     *
     * No configuration in either org triggers this today. It is a guard rail for tomorrow.
     */
    @TestVisible
    private static List<String> validateFilterDiscrimination(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> findings = new List<String>();
        if (configs == null || configs.isEmpty()) return findings;

        // object -> filter -> what that filter's rules actually do, as "field:pattern" strings.
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

    /**
     * Sandbox guard for batch start(). assertIsSandbox() throwing out of start() would abort the
     * job with the audit log stuck on "Running" and every bypass flag left enabled for the running
     * user. Returns false when the guard trips, having already closed the log and restored bypass.
     */
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
