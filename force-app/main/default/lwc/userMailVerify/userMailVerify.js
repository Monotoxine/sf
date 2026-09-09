import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";

import USER_OBJECT from "@salesforce/schema/User";
import BRAND_FIELD from "@salesforce/schema/User.TEKCO_Brand__c";

import getSettings from "@salesforce/apex/UserMailVerifyController.getSettings";
import getUnverifiedUsers from "@salesforce/apex/UserMailVerifyController.getUnverifiedUsers";
import launchVerification from "@salesforce/apex/UserMailVerifyController.launchVerification";
import launchPasswordReset from "@salesforce/apex/UserMailVerifyController.launchPasswordReset";

const COLUMNS = [
  { label: "Name", fieldName: "name", type: "text", sortable: true },
  { label: "Username", fieldName: "username", type: "text" },
  { label: "Email", fieldName: "email", type: "email" },
  { label: "Profile", fieldName: "profileName", type: "text" },
  {
    label: "Created",
    fieldName: "createdDate",
    type: "date",
    typeAttributes: { year: "numeric", month: "short", day: "2-digit" }
  },
  {
    label: ".invalid",
    fieldName: "invalidLabel",
    type: "text",
    cellAttributes: { class: { fieldName: "invalidClass" } },
    initialWidth: 90
  }
];

export default class UserMailVerify extends LightningElement {
  columns = COLUMNS;

  @track rows = [];
  @track brandOptions = [];

  selectedBrand;
  selectedIds = [];
  isLoading = false;
  isRunning = false;
  errorMessage;
  totalCount = 0;
  isTruncated = false;
  maxUsersPerRun;

  recordTypeId;

  @wire(getObjectInfo, { objectApiName: USER_OBJECT })
  handleObjectInfo({ data, error }) {
    if (data) {
      this.recordTypeId = data.defaultRecordTypeId;
    } else if (error) {
      this.reportError(error);
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$recordTypeId",
    fieldApiName: BRAND_FIELD
  })
  handleBrands({ data, error }) {
    if (data) {
      this.brandOptions = data.values.map((item) => ({
        label: item.label,
        value: item.value
      }));
    } else if (error) {
      this.reportError(error);
    }
  }

  @wire(getSettings)
  handleSettings({ data, error }) {
    if (data) {
      this.maxUsersPerRun = data.maxUsersPerRun;
    } else if (error) {
      this.reportError(error);
    }
  }

  get hasSelection() {
    return this.selectedIds.length > 0;
  }

  get isActionDisabled() {
    return !this.hasSelection || this.isRunning || this.isLoading;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmptyState() {
    return (
      !!this.selectedBrand &&
      !this.isLoading &&
      !this.hasRows &&
      !this.errorMessage
    );
  }

  get isOverCap() {
    return (
      !!this.maxUsersPerRun && this.selectedIds.length > this.maxUsersPerRun
    );
  }

  get selectionSummary() {
    if (!this.hasRows) {
      return "";
    }
    const cap = this.maxUsersPerRun
      ? ` (max ${this.maxUsersPerRun} per run)`
      : "";
    return `${this.selectedIds.length} of ${this.rows.length} selected${cap}`;
  }

  get truncationMessage() {
    return this.isTruncated
      ? `Showing the first ${this.rows.length} of ${this.totalCount} matching users. Narrow the selection or run several times.`
      : "";
  }

  handleBrandChange(event) {
    this.selectedBrand = event.detail.value;
    this.loadUsers();
  }

  handleRefresh() {
    this.loadUsers();
  }

  handleRowSelection(event) {
    this.selectedIds = event.detail.selectedRows.map((row) => row.id);
  }

  async handleVerify() {
    await this.run(launchVerification, "Email verification");
  }

  async handleReset() {
    const confirmed = await LightningConfirm.open({
      variant: "header",
      theme: "warning",
      label: "Reset passwords",
      message:
        `This will reset the password of ${this.selectedIds.length} user(s) and email them ` +
        "new credentials. Existing passwords stop working immediately and this cannot be undone."
    });
    if (confirmed) {
      await this.run(launchPasswordReset, "Password reset");
    }
  }

  async loadUsers() {
    if (!this.selectedBrand) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = undefined;
    this.selectedIds = [];
    try {
      const result = await getUnverifiedUsers({ brand: this.selectedBrand });
      this.rows = result.rows.map((row) => ({
        ...row,
        invalidLabel: row.hasInvalidSuffix ? "Yes" : "",
        invalidClass: row.hasInvalidSuffix ? "slds-text-color_error" : ""
      }));
      this.totalCount = result.totalCount;
      this.isTruncated = result.isTruncated;
    } catch (error) {
      this.rows = [];
      this.reportError(error);
    } finally {
      this.isLoading = false;
    }
  }

  async run(apexAction, label) {
    this.isRunning = true;
    try {
      const result = await apexAction({ userIds: this.selectedIds });
      this.toast(
        `${label} started`,
        `${result.queuedCount} user(s) queued. You will be notified when the run completes.`,
        "success"
      );
      // The run is asynchronous; the list only changes once users act on
      // the link, so it is reloaded rather than mutated optimistically.
      await this.loadUsers();
    } catch (error) {
      this.reportError(error);
    } finally {
      this.isRunning = false;
    }
  }

  reportError(error) {
    this.errorMessage = this.extractMessage(error);
    this.toast("Something went wrong", this.errorMessage, "error");
  }

  extractMessage(error) {
    if (!error) {
      return "Unknown error";
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    if (Array.isArray(error.body) && error.body.length) {
      return error.body[0].message;
    }
    return error.message || "Unknown error";
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
