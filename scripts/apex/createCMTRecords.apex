/**
 * createCMTRecords.apex
 *
 * Creates / updates all TEKCO_AnonymizationPattern__mdt and
 * TEKCO_AnonymizationFieldConfig__mdt records via direct DML upsert.
 *
 * Run with:
 *   sf apex run --file scripts/apex/createCMTRecords.apex
 */

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationPattern__mdt  (10 records)
// ─────────────────────────────────────────────────────────────────────────────

List<TEKCO_AnonymizationPattern__mdt> patterns = new List<TEKCO_AnonymizationPattern__mdt>{
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName        = 'NAME_FIRST_LETTER',
        MasterLabel          = 'Name First Letter',
        Description__c       = 'Keep only the first letter of the field value (e.g. "John" → "J.")',
        External_Id_Field__c = 'TEKCO_ExternalId__c',
        Is_Active__c         = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'PHONE_MASK',
        MasterLabel    = 'Phone Mask',
        Description__c = 'Keep first 4 digits, replace remaining digits with zeros (e.g. "+33612345678" → "+336 00 00 00 00")',
        Is_Active__c   = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName        = 'EMAIL_PLUS_EXTERNALID',
        MasterLabel          = 'Email Plus External Id',
        Description__c       = 'Replace email with base email + plus-addressing using the record external ID (e.g. sf_sap+EXT123@airliquide.com)',
        Base_Email__c        = 'sf_sap@airliquide.com',
        External_Id_Field__c = 'TEKCO_ExternalId__c',
        Is_Active__c         = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName        = 'EMAIL_PLUS_EXTERNALID_SUBDOMAIN',
        MasterLabel          = 'Email Plus External Id Subdomain',
        Description__c       = 'Same as EMAIL_PLUS_EXTERNALID but also appends the org subdomain to ensure uniqueness across orgs',
        Base_Email__c        = 'sf_sap@airliquide.com',
        External_Id_Field__c = 'TEKCO_ExternalId__c',
        Is_Active__c         = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'SSN_SEQUENTIAL',
        MasterLabel    = 'SSN Sequential',
        Description__c = 'Replace with a sequential fake SSN of configurable length (e.g. "000000000000001")',
        SSN_Length__c  = 15,
        Is_Active__c   = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'LOREM_IPSUM',
        MasterLabel    = 'Lorem Ipsum',
        Description__c = 'Replace free-text fields with a fixed Lorem Ipsum placeholder string',
        Is_Active__c   = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'KEEP',
        MasterLabel    = 'Keep',
        Description__c = 'Do not anonymize — keep the original value as-is (e.g. city names for analytics)',
        Is_Active__c   = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'ADDRESS_STREET_RANDOM',
        MasterLabel    = 'Address Street Random',
        Description__c = 'Replace street address with a generic anonymized placeholder (e.g. "1 Rue Anonyme")',
        Is_Active__c   = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'DELETE_CONTENT_DOCUMENT',
        MasterLabel    = 'Delete Content Document',
        Description__c = 'Delete all ContentDocument (files/attachments) linked to anonymized records — handled by a dedicated batch, not a field update',
        Is_Active__c   = true
    ),
    new TEKCO_AnonymizationPattern__mdt(
        DeveloperName  = 'EMAIL_MESSAGE_LOREM',
        MasterLabel    = 'Email Message Lorem',
        Description__c = 'Replace EmailMessage body/subject/addresses linked to anonymized records with Lorem Ipsum — handled by a dedicated batch',
        Is_Active__c   = true
    )
};

upsert patterns TEKCO_AnonymizationPattern__mdt.Fields.DeveloperName;
System.debug('Patterns OK: ' + patterns.size() + ' records upserted.');

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationFieldConfig__mdt  (23 Account field mappings)
// ─────────────────────────────────────────────────────────────────────────────

List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_FirstName',                    MasterLabel='Account FirstName',                    Object_API_Name__c='Account', Field_API_Name__c='FirstName',                       Pattern_Type__c='NAME_FIRST_LETTER',  Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_LastName',                     MasterLabel='Account LastName',                     Object_API_Name__c='Account', Field_API_Name__c='LastName',                        Pattern_Type__c='NAME_FIRST_LETTER',  Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_Phone',                        MasterLabel='Account Phone',                        Object_API_Name__c='Account', Field_API_Name__c='Phone',                           Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonMobilePhone',            MasterLabel='Account PersonMobilePhone',            Object_API_Name__c='Account', Field_API_Name__c='PersonMobilePhone',               Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_TEKCO_PersonMobilePhone__c',   MasterLabel='Account TEKCO PersonMobilePhone',      Object_API_Name__c='Account', Field_API_Name__c='TEKCO_PersonMobilePhone__c',      Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonOtherPhone',             MasterLabel='Account PersonOtherPhone',             Object_API_Name__c='Account', Field_API_Name__c='PersonOtherPhone',                Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PASCO_OtherPhone1__c',         MasterLabel='Account PASCO OtherPhone1',            Object_API_Name__c='Account', Field_API_Name__c='PASCO_OtherPhone1__c',            Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PASCO_OtherPhone2__c',         MasterLabel='Account PASCO OtherPhone2',            Object_API_Name__c='Account', Field_API_Name__c='PASCO_OtherPhone2__c',            Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_TEKCO_PersonOtherPhone__c',    MasterLabel='Account TEKCO PersonOtherPhone',       Object_API_Name__c='Account', Field_API_Name__c='TEKCO_PersonOtherPhone__c',       Pattern_Type__c='PHONE_MASK',         Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonEmail',                  MasterLabel='Account PersonEmail',                  Object_API_Name__c='Account', Field_API_Name__c='PersonEmail',                     Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCES_SecondEmail__c',         MasterLabel='Account ACCES SecondEmail',            Object_API_Name__c='Account', Field_API_Name__c='ACCES_SecondEmail__c',            Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCCO_Email__c',               MasterLabel='Account ACCCO Email',                  Object_API_Name__c='Account', Field_API_Name__c='ACCCO_Email__c',                  Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_TEKCO_PersonEmail__c',         MasterLabel='Account TEKCO PersonEmail',            Object_API_Name__c='Account', Field_API_Name__c='TEKCO_PersonEmail__c',            Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_FUNCA_InvoiceEmail__c',        MasterLabel='Account FUNCA InvoiceEmail',           Object_API_Name__c='Account', Field_API_Name__c='FUNCA_InvoiceEmail__c',           Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCMG_RecallEmail__c',         MasterLabel='Account ACCMG RecallEmail',            Object_API_Name__c='Account', Field_API_Name__c='ACCMG_RecallEmail__c',            Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCCO_SocialSecurityNumber__pc', MasterLabel='Account ACCCO SocialSecurityNumber', Object_API_Name__c='Account', Field_API_Name__c='ACCCO_SocialSecurityNumber__pc',  Pattern_Type__c='SSN_SEQUENTIAL',     Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_Description',                  MasterLabel='Account Description',                  Object_API_Name__c='Account', Field_API_Name__c='Description',                     Pattern_Type__c='LOREM_IPSUM',        Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonMailingStreet',          MasterLabel='Account PersonMailingStreet',          Object_API_Name__c='Account', Field_API_Name__c='PersonMailingStreet',             Pattern_Type__c='ADDRESS_STREET_RANDOM', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonMailingCity',            MasterLabel='Account PersonMailingCity',            Object_API_Name__c='Account', Field_API_Name__c='PersonMailingCity',               Pattern_Type__c='KEEP',               Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_BillingStreet',                MasterLabel='Account BillingStreet',                Object_API_Name__c='Account', Field_API_Name__c='BillingStreet',                   Pattern_Type__c='ADDRESS_STREET_RANDOM', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_BillingCity',                  MasterLabel='Account BillingCity',                  Object_API_Name__c='Account', Field_API_Name__c='BillingCity',                     Pattern_Type__c='KEEP',               Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ShippingStreet',               MasterLabel='Account ShippingStreet',               Object_API_Name__c='Account', Field_API_Name__c='ShippingStreet',                  Pattern_Type__c='ADDRESS_STREET_RANDOM', Is_Active__c=true),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ShippingCity',                 MasterLabel='Account ShippingCity',                 Object_API_Name__c='Account', Field_API_Name__c='ShippingCity',                    Pattern_Type__c='KEEP',               Is_Active__c=true)
};

upsert configs TEKCO_AnonymizationFieldConfig__mdt.Fields.DeveloperName;
System.debug('Field configs OK: ' + configs.size() + ' records upserted.');
