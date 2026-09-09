import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";

import getBrands from "@salesforce/apex/TEKCO_UserMailVerifyController.getBrands";
import getSettings from "@salesforce/apex/TEKCO_UserMailVerifyController.getSettings";
import getUsers from "@salesforce/apex/TEKCO_UserMailVerifyController.getUsers";
import launchVerification from "@salesforce/apex/TEKCO_UserMailVerifyController.launchVerification";
import launchPasswordReset from "@salesforce/apex/TEKCO_UserMailVerifyController.launchPasswordReset";

const VERIFICATION_OPTIONS = [
  { label: "Not verified", value: "UNVERIFIED" },
  { label: "Verified", value: "VERIFIED" },
  { label: "All", value: "ALL" }
];

const COLUMNS = [
  {
    label: "Name",
    fieldName: "recordUrl",
    type: "url",
    sortable: true,
    // Opened in a new tab on purpose: the selection lives in memory, and
    // navigating away in place would discard it.
    typeAttributes: { label: { fieldName: "name" }, target: "_blank" }
  },
  { label: "Username", fieldName: "username", type: "text" },
  { label: "Email", fieldName: "email", type: "email" },
  { label: "Profile", fieldName: "profileName", type: "text" },
  { label: "Brand", fieldName: "brand", type: "text" },
  {
    label: "Verified",
    fieldName: "verifiedLabel",
    type: "text",
    initialWidth: 90
  },
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

function verifiedLabelFor(isVerified) {
  if (isVerified === true) {
    return "Yes";
  }
  // Null means the org exposes no verification signal, which is not a "no".
  return isVerified === false ? "No" : "?";
}

export default class TekcoUserMailVerify extends LightningElement {
  columns = COLUMNS;
  verificationOptions = VERIFICATION_OPTIONS;

  // Default: the users this screen exists for. A reset also verifies, so an
  // already verified user is a legitimate target too, hence the other options.
  verificationFilter = "UNVERIFIED";

  @track rows = [];
  @track brandOptions = [];

  selectedBrands = [];
  selectedIds = [];
  isLoading = false;
  isRunning = false;
  errorMessage;
  totalCount = 0;
  isTruncated = false;
  maxUsersPerRun;
  isSandbox = false;

  brandsLoaded = false;
  searchTerm = "";

  // Served from Apex rather than the UI API: getPicklistValues needs a record
  // type id, and the User object does not support record types, so that wire
  // would never fire.
  @wire(getBrands)
  handleBrands({ data, error }) {
    if (data) {
      this.brandOptions = data.map((item) => ({
        label: item.label,
        value: item.value
      }));
      this.brandsLoaded = true;
    } else if (error) {
      this.brandsLoaded = true;
      this.reportError(error);
    }
  }

  @wire(getSettings)
  handleSettings({ data, error }) {
    if (data) {
      this.maxUsersPerRun = data.maxUsersPerRun;
      // Reset is offered in sandboxes only; production signs in through SSO.
      this.isSandbox = data.isSandbox === true;
    } else if (error) {
      this.reportError(error);
    }
  }

  /**
   * Filtered client-side: the rows for one brand are already loaded, so a
   * server round-trip per keystroke would buy nothing.
   */
  get filteredRows() {
    const term = this.searchTerm.trim().toLowerCase();
    if (!term) {
      return this.rows;
    }
    return this.rows.filter((row) =>
      [row.name, row.username, row.email, row.profileName].some(
        (value) => value && value.toLowerCase().includes(term)
      )
    );
  }

  get hasNoMatch() {
    return this.rows.length > 0 && this.filteredRows.length === 0;
  }

  get hasNoBrands() {
    return this.brandsLoaded && this.brandOptions.length === 0;
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

  get hasBrandSelection() {
    return this.selectedBrands.length > 0;
  }

  get showEmptyState() {
    return (
      this.hasBrandSelection &&
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
    // The count spans every loaded row, not just the visible ones: a selection
    // made before filtering still counts towards the run.
    const shown =
      this.filteredRows.length === this.rows.length
        ? ""
        : `, ${this.filteredRows.length} shown`;
    return `${this.selectedIds.length} of ${this.rows.length} selected${shown}${cap}`;
  }

  get truncationMessage() {
    return this.isTruncated
      ? `Showing the first ${this.rows.length} of ${this.totalCount} matching users. Narrow the selection or run several times.`
      : "";
  }

  handleVerificationChange(event) {
    this.verificationFilter = event.detail.value;
    this.loadUsers();
  }

  handleBrandChange(event) {
    this.selectedBrands = event.detail.value || [];
    this.loadUsers();
  }

  handleRefresh() {
    this.loadUsers();
  }

  handleSearch(event) {
    this.searchTerm = event.target.value || "";
  }

  /**
   * The datatable only reports the rows it currently shows, so a selection made
   * before filtering would be dropped. Selections outside the current filter
   * are preserved and only the visible ones are replaced.
   */
  handleRowSelection(event) {
    const visibleIds = new Set(this.filteredRows.map((row) => row.id));
    const selectedVisible = event.detail.selectedRows.map((row) => row.id);
    const merged = [
      ...this.selectedIds.filter((id) => !visibleIds.has(id)),
      ...selectedVisible
    ];

    // Assigning an equivalent array would re-render, feed selected-rows back
    // into the datatable and bounce another rowselection event.
    if (
      merged.slice().sort().join() !== this.selectedIds.slice().sort().join()
    ) {
      this.selectedIds = merged;
    }
  }

  async handleVerify() {
    await this.run(launchVerification, "Verification");
  }

  async handleReset() {
    const confirmed = await LightningConfirm.open({
      variant: "header",
      theme: "warning",
      label: "Verify and reset passwords",
      message:
        `This will reset the password of ${this.selectedIds.length} user(s) and email them ` +
        "new credentials. Existing passwords stop working immediately and this cannot be undone."
    });
    if (confirmed) {
      await this.run(launchPasswordReset, "Verify and reset");
    }
  }

  async loadUsers() {
    if (!this.hasBrandSelection) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = undefined;
    this.selectedIds = [];
    this.searchTerm = "";
    try {
      const result = await getUsers({
        brands: this.selectedBrands,
        verificationFilter: this.verificationFilter
      });
      this.rows = result.rows.map((row) => ({
        ...row,
        recordUrl: `/lightning/r/User/${row.id}/view`,
        verifiedLabel: verifiedLabelFor(row.isVerified),
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
