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
// TEKCO_AnonymizationFieldConfig__mdt  (23 Account field mappings)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationFieldConfig__mdt records  (Account — 24 records)
//
// New fields:
//   Record_Type_Developer_Name__c — optional RT filter (blank = all RTs)
//   Delete_History__c             — true = erase field history after anonymization
//
// Pattern DELETE_CONTENT_DOCUMENT uses Field_API_Name__c = 'ContentDocument'
// as a placeholder (no real field). Triggers ContentDocumentBatch for Account.
// ─────────────────────────────────────────────────────────────────────────────

List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
    // Names — history deleted
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_FirstName',                    MasterLabel='Account FirstName',                    Object_API_Name__c='Account', Field_API_Name__c='FirstName',                       Pattern_Type__c='NAME_FIRST_LETTER',     Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_LastName',                     MasterLabel='Account LastName',                     Object_API_Name__c='Account', Field_API_Name__c='LastName',                        Pattern_Type__c='NAME_FIRST_LETTER',     Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    // Phones
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_Phone',                        MasterLabel='Account Phone',                        Object_API_Name__c='Account', Field_API_Name__c='Phone',                           Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonMobilePhone',            MasterLabel='Account PersonMobilePhone',            Object_API_Name__c='Account', Field_API_Name__c='PersonMobilePhone',               Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_TEKCO_PersonMobilePhone__c',   MasterLabel='Account TEKCO PersonMobilePhone',      Object_API_Name__c='Account', Field_API_Name__c='TEKCO_PersonMobilePhone__c',      Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonOtherPhone',             MasterLabel='Account PersonOtherPhone',             Object_API_Name__c='Account', Field_API_Name__c='PersonOtherPhone',                Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PASCO_OtherPhone1__c',         MasterLabel='Account PASCO OtherPhone1',            Object_API_Name__c='Account', Field_API_Name__c='PASCO_OtherPhone1__c',            Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PASCO_OtherPhone2__c',         MasterLabel='Account PASCO OtherPhone2',            Object_API_Name__c='Account', Field_API_Name__c='PASCO_OtherPhone2__c',            Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_TEKCO_PersonOtherPhone__c',    MasterLabel='Account TEKCO PersonOtherPhone',       Object_API_Name__c='Account', Field_API_Name__c='TEKCO_PersonOtherPhone__c',       Pattern_Type__c='PHONE_MASK',            Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    // Emails — history deleted
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonEmail',                  MasterLabel='Account PersonEmail',                  Object_API_Name__c='Account', Field_API_Name__c='PersonEmail',                     Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCES_SecondEmail__c',         MasterLabel='Account ACCES SecondEmail',            Object_API_Name__c='Account', Field_API_Name__c='ACCES_SecondEmail__c',            Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCCO_Email__c',               MasterLabel='Account ACCCO Email',                  Object_API_Name__c='Account', Field_API_Name__c='ACCCO_Email__c',                  Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_TEKCO_PersonEmail__c',         MasterLabel='Account TEKCO PersonEmail',            Object_API_Name__c='Account', Field_API_Name__c='TEKCO_PersonEmail__c',            Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_FUNCA_InvoiceEmail__c',        MasterLabel='Account FUNCA InvoiceEmail',           Object_API_Name__c='Account', Field_API_Name__c='FUNCA_InvoiceEmail__c',           Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCMG_RecallEmail__c',         MasterLabel='Account ACCMG RecallEmail',            Object_API_Name__c='Account', Field_API_Name__c='ACCMG_RecallEmail__c',            Pattern_Type__c='EMAIL_PLUS_EXTERNALID', Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    // SSN — history deleted
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ACCCO_SocialSecurityNumber__pc', MasterLabel='Account ACCCO SocialSecurityNumber', Object_API_Name__c='Account', Field_API_Name__c='ACCCO_SocialSecurityNumber__pc',  Pattern_Type__c='SSN_SEQUENTIAL',        Is_Active__c=true, Delete_History__c=true,  Record_Type_Developer_Name__c=null),
    // Free text
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_Description',                  MasterLabel='Account Description',                  Object_API_Name__c='Account', Field_API_Name__c='Description',                     Pattern_Type__c='LOREM_IPSUM',           Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    // Addresses
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonMailingStreet',          MasterLabel='Account PersonMailingStreet',          Object_API_Name__c='Account', Field_API_Name__c='PersonMailingStreet',             Pattern_Type__c='ADDRESS_STREET_RANDOM', Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_PersonMailingCity',            MasterLabel='Account PersonMailingCity',            Object_API_Name__c='Account', Field_API_Name__c='PersonMailingCity',               Pattern_Type__c='KEEP',                  Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_BillingStreet',                MasterLabel='Account BillingStreet',                Object_API_Name__c='Account', Field_API_Name__c='BillingStreet',                   Pattern_Type__c='ADDRESS_STREET_RANDOM', Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_BillingCity',                  MasterLabel='Account BillingCity',                  Object_API_Name__c='Account', Field_API_Name__c='BillingCity',                     Pattern_Type__c='KEEP',                  Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ShippingStreet',               MasterLabel='Account ShippingStreet',               Object_API_Name__c='Account', Field_API_Name__c='ShippingStreet',                  Pattern_Type__c='ADDRESS_STREET_RANDOM', Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ShippingCity',                 MasterLabel='Account ShippingCity',                 Object_API_Name__c='Account', Field_API_Name__c='ShippingCity',                    Pattern_Type__c='KEEP',                  Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null),
    // ContentDocument deletion for Account (Field_API_Name__c is a placeholder)
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Account_ContentDocument',              MasterLabel='Account ContentDocument',              Object_API_Name__c='Account', Field_API_Name__c='ContentDocument',                 Pattern_Type__c='DELETE_CONTENT_DOCUMENT', Is_Active__c=true, Delete_History__c=false, Record_Type_Developer_Name__c=null)
};

upsert configs TEKCO_AnonymizationFieldConfig__mdt.Fields.DeveloperName;
System.debug('Field configs OK: ' + configs.size() + ' records upserted.');
