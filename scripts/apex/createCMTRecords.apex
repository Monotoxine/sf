/**
 * createCMTRecords.apex
 *
 * Creates all TEKCO_AnonymizationPattern__mdt and TEKCO_AnonymizationFieldConfig__mdt
 * Custom Metadata Type records via the Metadata API.
 *
 * Run with:
 *   sf apex run --file scripts/apex/createCMTRecords.apex
 *
 * NOTE: CMT records cannot be created via DML — Metadata.DeployContainer is required.
 * The deploy is asynchronous; check Setup > Deployment Status for results.
 */

Metadata.DeployContainer container = new Metadata.DeployContainer();

// ─────────────────────────────────────────────────────────────────────────────
// Helper closure (inner class workaround via method)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationPattern__mdt records
// ─────────────────────────────────────────────────────────────────────────────

// 1. NAME_FIRST_LETTER
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.NAME_FIRST_LETTER';
    r.label   = 'Name First Letter';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c';        v.value = 'Keep only the first letter of the field value (e.g. "John" → "J.")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'External_Id_Field__c';  v.value = 'TEKCO_ExternalId__c'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';          v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 2. PHONE_MASK
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.PHONE_MASK';
    r.label   = 'Phone Mask';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Keep first 4 digits, replace remaining digits with zeros (e.g. "+33612345678" → "+336 00 00 00 00")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 3. EMAIL_PLUS_EXTERNALID
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.EMAIL_PLUS_EXTERNALID';
    r.label   = 'Email Plus External Id';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c';       v.value = 'Replace email with base email + plus-addressing using the record external ID (e.g. sf_sap+EXT123@airliquide.com)'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Base_Email__c';        v.value = 'sf_sap@airliquide.com'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'External_Id_Field__c'; v.value = 'TEKCO_ExternalId__c'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';         v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 4. EMAIL_PLUS_EXTERNALID_SUBDOMAIN
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.EMAIL_PLUS_EXTERNALID_SUBDOMAIN';
    r.label   = 'Email Plus External Id Subdomain';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c';       v.value = 'Same as EMAIL_PLUS_EXTERNALID but also appends the org subdomain to ensure uniqueness across orgs'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Base_Email__c';        v.value = 'sf_sap@airliquide.com'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'External_Id_Field__c'; v.value = 'TEKCO_ExternalId__c'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';         v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 5. SSN_SEQUENTIAL
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.SSN_SEQUENTIAL';
    r.label   = 'SSN Sequential';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Replace with a sequential fake SSN of configurable length (e.g. "000000000000001")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'SSN_Length__c';  v.value = 15; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 6. LOREM_IPSUM
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.LOREM_IPSUM';
    r.label   = 'Lorem Ipsum';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Replace free-text fields with a fixed Lorem Ipsum placeholder string'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 7. KEEP
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.KEEP';
    r.label   = 'Keep';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Do not anonymize — keep the original value as-is (e.g. city names for analytics)'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 8. ADDRESS_STREET_RANDOM
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.ADDRESS_STREET_RANDOM';
    r.label   = 'Address Street Random';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Replace street address with a generic anonymized placeholder (e.g. "1 Rue Anonyme")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 9. DELETE_CONTENT_DOCUMENT
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.DELETE_CONTENT_DOCUMENT';
    r.label   = 'Delete Content Document';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Delete all ContentDocument (files/attachments) linked to anonymized records — handled by a dedicated batch, not a field update'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 10. EMAIL_MESSAGE_LOREM
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.EMAIL_MESSAGE_LOREM';
    r.label   = 'Email Message Lorem';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Description__c'; v.value = 'Replace EmailMessage body/subject/addresses linked to anonymized records with Lorem Ipsum — handled by a dedicated batch'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationFieldConfig__mdt records  (Account — 23 records)
// ─────────────────────────────────────────────────────────────────────────────

List<List<String>> fieldMappings = new List<List<String>>{
    new List<String>{'Account_FirstName',                   'Account',  'FirstName',                       'NAME_FIRST_LETTER'},
    new List<String>{'Account_LastName',                    'Account',  'LastName',                        'NAME_FIRST_LETTER'},
    new List<String>{'Account_Phone',                       'Account',  'Phone',                           'PHONE_MASK'},
    new List<String>{'Account_PersonMobilePhone',           'Account',  'PersonMobilePhone',               'PHONE_MASK'},
    new List<String>{'Account_TEKCO_PersonMobilePhone',  'Account',  'TEKCO_PersonMobilePhone__c',      'PHONE_MASK'},
    new List<String>{'Account_PersonOtherPhone',            'Account',  'PersonOtherPhone',                'PHONE_MASK'},
    new List<String>{'Account_PASCO_OtherPhone1',        'Account',  'PASCO_OtherPhone1__c',            'PHONE_MASK'},
    new List<String>{'Account_PASCO_OtherPhone2',        'Account',  'PASCO_OtherPhone2__c',            'PHONE_MASK'},
    new List<String>{'Account_TEKCO_PersonOtherPhone',   'Account',  'TEKCO_PersonOtherPhone__c',       'PHONE_MASK'},
    new List<String>{'Account_PersonEmail',                 'Account',  'PersonEmail',                     'EMAIL_PLUS_EXTERNALID'},
    new List<String>{'Account_ACCES_SecondEmail',        'Account',  'ACCES_SecondEmail__c',            'EMAIL_PLUS_EXTERNALID'},
    new List<String>{'Account_ACCCO_Email',              'Account',  'ACCCO_Email__c',                  'EMAIL_PLUS_EXTERNALID'},
    new List<String>{'Account_TEKCO_PersonEmail',        'Account',  'TEKCO_PersonEmail__c',            'EMAIL_PLUS_EXTERNALID'},
    new List<String>{'Account_FUNCA_InvoiceEmail',       'Account',  'FUNCA_InvoiceEmail__c',           'EMAIL_PLUS_EXTERNALID'},
    new List<String>{'Account_ACCMG_RecallEmail',        'Account',  'ACCMG_RecallEmail__c',            'EMAIL_PLUS_EXTERNALID'},
    new List<String>{'Account_ACCCO_SocialSecurityNumber', 'Account', 'ACCCO_SocialSecurityNumber__pc','SSN_SEQUENTIAL'},
    new List<String>{'Account_Description',                 'Account',  'Description',                     'LOREM_IPSUM'},
    new List<String>{'Account_PersonMailingStreet',         'Account',  'PersonMailingStreet',             'ADDRESS_STREET_RANDOM'},
    new List<String>{'Account_PersonMailingCity',           'Account',  'PersonMailingCity',               'KEEP'},
    new List<String>{'Account_BillingStreet',               'Account',  'BillingStreet',                   'ADDRESS_STREET_RANDOM'},
    new List<String>{'Account_BillingCity',                 'Account',  'BillingCity',                     'KEEP'},
    new List<String>{'Account_ShippingStreet',              'Account',  'ShippingStreet',                  'ADDRESS_STREET_RANDOM'},
    new List<String>{'Account_ShippingCity',                'Account',  'ShippingCity',                    'KEEP'}
};

for (List<String> m : fieldMappings) {
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationFieldConfig__mdt.' + m[0];
    r.label   = m[0].replace('_', ' ');
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Object_API_Name__c'; v.value = m[1]; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Field_API_Name__c';  v.value = m[2]; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Pattern_Type__c';    v.value = m[3]; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Is_Active__c';       v.value = true;  r.values.add(v);
    container.addMetadata(r);
}

// ─────────────────────────────────────────────────────────────────────────────
// Enqueue deployment
// ─────────────────────────────────────────────────────────────────────────────
Id jobId = Metadata.Operations.enqueueDeployment(container, null);
System.debug('CMT deployment enqueued. Job ID: ' + jobId);
System.debug('Check progress: Setup → Deployment Status');
