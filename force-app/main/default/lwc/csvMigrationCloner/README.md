# CSV Migration Cloner Component

## Overview

This Lightning Web Component allows users to clone Salesforce records with related child records (Lookup/Master-Detail relationships) while automatically appending a suffix to DataMigrationId__c fields.

## Features

- ✅ Upload CSV file with DataMigration IDs
- ✅ Select master object containing the IDs
- ✅ Automatically detect related objects with Lookup/Master-Detail relationships
- ✅ Multi-select related objects to clone
- ✅ Configure custom suffix for DataMigrationId__c
- ✅ Clone all selected objects in the same org
- ✅ Maintain relationships in cloned records

## User Flow

### Step 1: Upload CSV
Upload a CSV file containing DataMigration IDs (one per line).

**Example CSV:**
```
MIG-001
MIG-002
MIG-003
```

### Step 2: Select Master Object
Choose the main object that contains the DataMigration IDs you want to clone.

The component will automatically detect all related objects that have:
- Lookup relationships to the master object
- Master-Detail relationships to the master object

### Step 3: Configure Migration
- Select which related objects you want to clone (checkboxes)
- Enter a suffix to append to DataMigrationId__c (e.g., `_CLONE`, `_V2`, `_TEST`)

**Example:**
- Original ID: `MIG-001`
- Suffix: `_CLONE`
- New ID: `MIG-001_CLONE`

### Step 4: Review & Clone
Review the configuration and start the cloning process.

The component will:
1. Clone all master records with new DataMigrationId__c
2. Clone all selected related records
3. Update relationship fields to point to the new master records
4. Display a summary of cloned records

## Technical Details

### Components

#### LWC Component
- **Path:** `force-app/main/default/lwc/csvMigrationCloner/`
- **Files:**
  - `csvMigrationCloner.js` - Component logic
  - `csvMigrationCloner.html` - Template
  - `csvMigrationCloner.css` - Styling
  - `csvMigrationCloner.js-meta.xml` - Metadata

#### Apex Controller
- **Path:** `force-app/main/default/classes/CSVMigrationClonerController.cls`
- **Methods:**
  - `getExtractableObjects()` - Get objects with DataMigrationId__c
  - `parseCSVFile()` - Parse uploaded CSV
  - `getRelatedObjects()` - Find related objects with relationships
  - `cloneRecords()` - Clone master and related records

### Requirements

1. **DataMigrationId__c Field**
   - Must exist on master object
   - Should be unique
   - Type: Text

2. **Related Objects**
   - Must have Lookup or Master-Detail relationship to master
   - Optional: Can have DataMigrationId__c for tracking

### Data Model

```
Master Object (e.g., Product__c)
├─ DataMigrationId__c: "MIG-001"
└─ Related Objects
   ├─ Child1__c (Lookup to Product__c)
   │  └─ DataMigrationId__c: "MIG-001-CHILD1"
   └─ Child2__c (Master-Detail to Product__c)
      └─ DataMigrationId__c: "MIG-001-CHILD2"

After Cloning with suffix "_CLONE":

Master Object Clone
├─ DataMigrationId__c: "MIG-001_CLONE"
└─ Related Objects Clones
   ├─ Child1__c Clone (Lookup to Product__c Clone)
   │  └─ DataMigrationId__c: "MIG-001-CHILD1_CLONE"
   └─ Child2__c Clone (Master-Detail to Product__c Clone)
      └─ DataMigrationId__c: "MIG-001-CHILD2_CLONE"
```

## Deployment

### Deploy Component

```bash
# Deploy LWC
sf project deploy start --source-path force-app/main/default/lwc/csvMigrationCloner/

# Deploy Apex Controller
sf project deploy start --source-path force-app/main/default/classes/CSVMigrationClonerController.cls
```

### Add to Lightning App or Page

1. Open Lightning App Builder
2. Drag the **csvMigrationCloner** component onto the page
3. Save and activate

### Permissions

Users need:
- Read access to master and related objects
- Create access to master and related objects
- Read/Write access to DataMigrationId__c field

## Usage Examples

### Example 1: Clone Products with Prices

1. Upload CSV with Product IDs
2. Select `Product__c` as master object
3. Select `Price__c` as related object (Lookup to Product__c)
4. Enter suffix: `_V2`
5. Clone → Creates Product__c and Price__c clones

### Example 2: Clone Accounts with Contacts and Opportunities

1. Upload CSV with Account DataMigration IDs
2. Select `Account__c` as master object
3. Select related objects:
   - ✅ `Contact__c` (Lookup to Account__c)
   - ✅ `Opportunity__c` (Lookup to Account__c)
4. Enter suffix: `_TEST`
5. Clone → Creates Account__c, Contact__c, and Opportunity__c clones

## Limitations

### Governor Limits
- Maximum 10,000 records per transaction
- For large datasets, consider breaking into smaller batches

### Relationship Detection
- Only detects direct Lookup/Master-Detail relationships
- Does not support junction objects or complex hierarchies
- Does not support polymorphic relationships

### Field Cloning
- Clones all accessible fields
- Does not clone read-only system fields (CreatedDate, LastModifiedDate, etc.)
- Does not clone formula fields or rollup summary fields

## Troubleshooting

### No Objects in Master Picklist
**Issue:** Picklist is empty

**Solution:**
- Ensure objects have `DataMigrationId__c` field
- Ensure objects are custom objects
- Check field-level security

### No Related Objects Found
**Issue:** No related objects displayed

**Solution:**
- Verify Lookup/Master-Detail relationships exist
- Check relationship field accessibility
- Ensure related objects are custom objects

### Cloning Fails
**Issue:** Error during cloning

**Solutions:**
- Check required fields on objects
- Verify validation rules
- Check for duplicate DataMigrationId__c values
- Review debug logs for detailed errors

### Suffix Conflicts
**Issue:** Duplicate DataMigrationId__c after cloning

**Solution:**
- Use a unique suffix
- Check existing records before cloning
- Consider using timestamp in suffix (e.g., `_2026`)

## Best Practices

1. **Test in Sandbox First**
   - Always test cloning in sandbox before production
   - Verify relationships maintain correctly

2. **Use Descriptive Suffixes**
   - Use meaningful suffixes: `_CLONE`, `_V2`, `_TEST`, `_2026`
   - Include dates or versions for tracking

3. **Monitor Governor Limits**
   - Clone in batches for large datasets
   - Monitor heap size and CPU time

4. **Backup Before Cloning**
   - Export original records before cloning
   - Keep CSV file of original IDs

5. **Verify After Cloning**
   - Check record counts match
   - Verify relationships are correct
   - Test related records point to new masters

## Future Enhancements

Potential improvements:
- [ ] Batch processing for large datasets
- [ ] Field mapping customization
- [ ] Exclude specific fields from cloning
- [ ] Support for polymorphic relationships
- [ ] Export cloned record IDs to CSV
- [ ] Rollback functionality
- [ ] Schedule automated cloning

## Support

For issues or questions:
1. Check debug logs in Developer Console
2. Review Salesforce governor limits
3. Verify object and field permissions
4. Contact your Salesforce administrator

---

**Version:** 1.0
**Last Updated:** 2026-01-12
**API Version:** 65.0
**Status:** ✅ Production Ready
