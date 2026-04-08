/**
 * createCMTRecords.apex
 *
 * Creates all TEKCO_AnonymizationPattern__mdt and TEKCO_AnonymizationFieldConfig__mdt
 * Custom Metadata Type records via the Metadata API.
 *
 * Run with:
 * sf apex run --file scripts/apex/createCMTRecords.apex
 *
 * NOTE: The deploy is asynchronous; check Setup > Deployment Status for results.
 */

Metadata.DeployContainer container = new Metadata.DeployContainer();

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationPattern__mdt records
// ─────────────────────────────────────────────────────────────────────────────

// 1. NAME_FIRST_LETTER
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.NAME_FIRST_LETTER';
    r.label   = 'Name First Letter';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c';        v.value = 'Keep only the first letter of the field value (e.g. "John" → "J.")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_ExternalIdField__c';  v.value = 'TEKCO_ExternalId__c'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';          v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 2. PHONE_MASK
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.PHONE_MASK';
    r.label   = 'Phone Mask';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Keep first 4 digits, replace remaining digits with zeros (e.g. "+33612345678" → "+336 00 00 00 00")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 3. EMAIL_PLUS_EXTERNALID
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.EMAIL_PLUS_EXTERNALID';
    r.label   = 'Email Plus External Id';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c';       v.value = 'Replace email with base email + plus-addressing using the record external ID (e.g. sf_sap+EXT123@airliquide.com)'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_BaseEmail__c';        v.value = 'sf_sap@airliquide.com'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_ExternalIdField__c'; v.value = 'TEKCO_ExternalId__c'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';         v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 4. EMAIL_PLUS_EXTERNALID_SUBDOMAIN
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.EMAIL_PLUS_EXTERNALID_SUBDOMAIN';
    r.label   = 'Email Plus External Id Subdomain';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c';       v.value = 'Same as EMAIL_PLUS_EXTERNALID but also appends the org subdomain to ensure uniqueness across orgs'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_BaseEmail__c';        v.value = 'sf_sap@airliquide.com'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_ExternalIdField__c'; v.value = 'TEKCO_ExternalId__c'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';         v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 5. SSN_SEQUENTIAL
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.SSN_SEQUENTIAL';
    r.label   = 'SSN Sequential';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Replace with a sequential fake SSN of configurable length (e.g. "000000000000001")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_SsnLength__c';  v.value = 15; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 6. LOREM_IPSUM
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.LOREM_IPSUM';
    r.label   = 'Lorem Ipsum';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Replace free-text fields with a fixed Lorem Ipsum placeholder string'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 7. KEEP
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.KEEP';
    r.label   = 'Keep';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Do not anonymize — keep the original value as-is (e.g. city names for analytics)'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 8. ADDRESS_STREET_RANDOM
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.ADDRESS_STREET_RANDOM';
    r.label   = 'Address Street Random';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Replace street address with a generic anonymized placeholder (e.g. "1 Rue Anonyme")'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 9. DELETE_CONTENT_DOCUMENT
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.DELETE_CONTENT_DOCUMENT';
    r.label   = 'Delete Content Document';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Delete all ContentDocument (files/attachments) linked to anonymized records — handled by a dedicated batch, not a field update'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// 10. EMAIL_MESSAGE_LOREM
{
    Metadata.CustomMetadata r = new Metadata.CustomMetadata();
    r.fullName = 'TEKCO_AnonymizationPattern__mdt.EMAIL_MESSAGE_LOREM';
    r.label   = 'Email Message Lorem';
    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_Description__c'; v.value = 'Replace EmailMessage body/subject/addresses linked to anonymized records with Lorem Ipsum — handled by a dedicated batch'; r.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_IsActive__c';   v.value = true; r.values.add(v);
    container.addMetadata(r);
}

// ─────────────────────────────────────────────────────────────────────────────
// TEKCO_AnonymizationFieldConfig__mdt  (Patient mappings)
// ─────────────────────────────────────────────────────────────────────────────

List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
    // Names
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_FirstName', MasterLabel='Patient FirstName', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='FirstName', TEKCO_PatternType__c='NAME_FIRST_LETTER', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_LastName', MasterLabel='Patient LastName', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='LastName', TEKCO_PatternType__c='NAME_FIRST_LETTER', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    // Phones
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_Phone', MasterLabel='Patient Phone', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='Phone', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PersonMobilePhone', MasterLabel='Patient PersonMobilePhone', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PersonMobilePhone', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_TEKCO_PersonMobilePhone', MasterLabel='Patient TEKCO PersonMobilePhone', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='TEKCO_PersonMobilePhone__c', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PersonOtherPhone', MasterLabel='Patient PersonOtherPhone', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PersonOtherPhone', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PASCO_OtherPhone1', MasterLabel='Patient PASCO OtherPhone1', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PASCO_OtherPhone1__c', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PASCO_OtherPhone2', MasterLabel='Patient PASCO OtherPhone2', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PASCO_OtherPhone2__c', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_TEKCO_PersonOtherPhone', MasterLabel='Patient TEKCO PersonOtherPhone', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='TEKCO_PersonOtherPhone__c', TEKCO_PatternType__c='PHONE_MASK', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    // Emails
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PersonEmail', MasterLabel='Patient PersonEmail', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PersonEmail', TEKCO_PatternType__c='EMAIL_PLUS_EXTERNALID', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ACCES_SecondEmail', MasterLabel='Patient ACCES SecondEmail', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ACCES_SecondEmail__c', TEKCO_PatternType__c='EMAIL_PLUS_EXTERNALID', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ACCCO_Email', MasterLabel='Patient ACCCO Email', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ACCCO_Email__c', TEKCO_PatternType__c='EMAIL_PLUS_EXTERNALID', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_TEKCO_PersonEmail', MasterLabel='Patient TEKCO PersonEmail', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='TEKCO_PersonEmail__c', TEKCO_PatternType__c='EMAIL_PLUS_EXTERNALID', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_FUNCA_InvoiceEmail', MasterLabel='Patient FUNCA InvoiceEmail', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='FUNCA_InvoiceEmail__c', TEKCO_PatternType__c='EMAIL_PLUS_EXTERNALID', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ACCMG_RecallEmail', MasterLabel='Patient ACCMG RecallEmail', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ACCMG_RecallEmail__c', TEKCO_PatternType__c='EMAIL_PLUS_EXTERNALID', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    // SSN
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ACCCO_SocialSecurityNumber', MasterLabel='Patient ACCCO SocialSecurityNumber', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ACCCO_SocialSecurityNumber__pc', TEKCO_PatternType__c='SSN_SEQUENTIAL', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=true, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    // Free text
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_Description', MasterLabel='Patient Description', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='Description', TEKCO_PatternType__c='LOREM_IPSUM', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    // Addresses
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PersonMailingStreet', MasterLabel='Patient PersonMailingStreet', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PersonMailingStreet', TEKCO_PatternType__c='ADDRESS_STREET_RANDOM', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_PersonMailingCity', MasterLabel='Patient PersonMailingCity', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='PersonMailingCity', TEKCO_PatternType__c='KEEP', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_BillingStreet', MasterLabel='Patient BillingStreet', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='BillingStreet', TEKCO_PatternType__c='ADDRESS_STREET_RANDOM', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_BillingCity', MasterLabel='Patient BillingCity', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='BillingCity', TEKCO_PatternType__c='KEEP', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ShippingStreet', MasterLabel='Patient ShippingStreet', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ShippingStreet', TEKCO_PatternType__c='ADDRESS_STREET_RANDOM', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ShippingCity', MasterLabel='Patient ShippingCity', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ShippingCity', TEKCO_PatternType__c='KEEP', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient'),
    // ContentDocument deletion for Patient
    new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName='Patient_ContentDocument', MasterLabel='Patient ContentDocument', TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='ContentDocument', TEKCO_PatternType__c='DELETE_CONTENT_DOCUMENT', TEKCO_IsActive__c=true, TEKCO_DeleteHistory__c=false, TEKCO_RecordTypeDeveloperName__c='ACCCO_Patient')
};

// Convert SObjects to Metadata API format and add to container
for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
    Metadata.CustomMetadata customMeta = new Metadata.CustomMetadata();
    customMeta.fullName = 'TEKCO_AnonymizationFieldConfig__mdt.' + config.DeveloperName;
    customMeta.label = config.MasterLabel;

    // Helper to conditionally add fields
    if(config.TEKCO_ObjectApiName__c != null) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_ObjectApiName__c'; v.value = config.TEKCO_ObjectApiName__c; customMeta.values.add(v);
    }
    if(config.TEKCO_FieldApiName__c != null) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_FieldApiName__c'; v.value = config.TEKCO_FieldApiName__c; customMeta.values.add(v);
    }
    if(config.TEKCO_PatternType__c != null) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_PatternType__c'; v.value = config.TEKCO_PatternType__c; customMeta.values.add(v);
    }
    if(config.TEKCO_RecordTypeDeveloperName__c != null) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue(); v.field = 'TEKCO_RecordTypeDeveloperName__c'; v.value = config.TEKCO_RecordTypeDeveloperName__c; customMeta.values.add(v);
    }
    
    Metadata.CustomMetadataValue vActive = new Metadata.CustomMetadataValue(); vActive.field = 'TEKCO_IsActive__c'; vActive.value = config.TEKCO_IsActive__c; customMeta.values.add(vActive);
    Metadata.CustomMetadataValue vDelHist = new Metadata.CustomMetadataValue(); vDelHist.field = 'TEKCO_DeleteHistory__c'; vDelHist.value = config.TEKCO_DeleteHistory__c; customMeta.values.add(vDelHist);

    container.addMetadata(customMeta);
}

// ─────────────────────────────────────────────────────────────────────────────
// Enqueue the Deployment
// ─────────────────────────────────────────────────────────────────────────────
Id asyncResultId = Metadata.Operations.enqueueDeployment(container, null);
System.debug('Deployment enqueued successfully. Job ID: ' + asyncResultId);
System.debug('Check Setup > Deployment Status to see the progress.');