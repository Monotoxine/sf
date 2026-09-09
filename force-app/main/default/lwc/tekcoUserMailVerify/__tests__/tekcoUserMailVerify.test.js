import { createElement } from "@lwc/engine-dom";
import TekcoUserMailVerify from "c/tekcoUserMailVerify";
import getBrands from "@salesforce/apex/TEKCO_UserMailVerifyController.getBrands";
import getUnverifiedUsers from "@salesforce/apex/TEKCO_UserMailVerifyController.getUnverifiedUsers";
import launchVerification from "@salesforce/apex/TEKCO_UserMailVerifyController.launchVerification";

// Required inside the factory: jest.mock is hoisted and cannot capture an
// out-of-scope import.
jest.mock(
  "@salesforce/apex/TEKCO_UserMailVerifyController.getBrands",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TEKCO_UserMailVerifyController.getSettings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TEKCO_UserMailVerifyController.getUnverifiedUsers",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TEKCO_UserMailVerifyController.launchVerification",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TEKCO_UserMailVerifyController.launchPasswordReset",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("lightning/confirm", () => ({ default: { open: jest.fn() } }), {
  virtual: true
});

const USERS = {
  rows: [
    {
      id: "005000000000001AAA",
      name: "Ada Lovelace",
      username: "ada@example.com",
      email: "ada@example.com",
      profileName: "Standard User",
      createdDate: "2026-01-01T00:00:00.000Z",
      hasInvalidSuffix: false
    },
    {
      id: "005000000000002AAA",
      name: "Alan Turing",
      username: "alan@example.com",
      email: "alan@example.com.invalid",
      profileName: "Standard User",
      createdDate: "2026-01-02T00:00:00.000Z",
      hasInvalidSuffix: true
    }
  ],
  totalCount: 2,
  isTruncated: false
};

function createComponent() {
  const element = createElement("c-tekco-user-mail-verify", {
    is: TekcoUserMailVerify
  });
  document.body.appendChild(element);
  return element;
}

async function selectBrand(element, brand = "ACME") {
  const combobox = element.shadowRoot.querySelector("lightning-combobox");
  combobox.dispatchEvent(
    new CustomEvent("change", { detail: { value: brand } })
  );
  await Promise.resolve();
  await Promise.resolve();
}

describe("c-tekco-user-mail-verify", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("fills the brand combobox from Apex", async () => {
    const element = createComponent();

    getBrands.emit([
      { label: "Acme", value: "ACME" },
      { label: "Globex", value: "GLOBEX" }
    ]);
    await Promise.resolve();

    const combobox = element.shadowRoot.querySelector("lightning-combobox");
    expect(combobox.options).toEqual([
      { label: "Acme", value: "ACME" },
      { label: "Globex", value: "GLOBEX" }
    ]);
  });

  it("shows no table before a brand is chosen", () => {
    const element = createComponent();
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
  });

  it("loads users for the selected brand", async () => {
    getUnverifiedUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrand(element);

    expect(getUnverifiedUsers).toHaveBeenCalledWith({ brand: "ACME" });
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table).not.toBeNull();
    expect(table.data).toHaveLength(2);
  });

  it("flags addresses carrying the .invalid suffix", async () => {
    getUnverifiedUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrand(element);

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0].invalidLabel).toBe("");
    expect(table.data[1].invalidLabel).toBe("Yes");
  });

  it("keeps the action buttons disabled until rows are selected", async () => {
    getUnverifiedUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrand(element);

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const verify = Array.from(buttons).find(
      (b) => b.label === "Send verification"
    );
    expect(verify.disabled).toBe(true);
  });

  it("sends only the selected user ids to Apex", async () => {
    getUnverifiedUsers.mockResolvedValue(USERS);
    launchVerification.mockResolvedValue({
      queuedCount: 1,
      jobId: "707000000000001"
    });
    const element = createComponent();

    await selectBrand(element);

    const table = element.shadowRoot.querySelector("lightning-datatable");
    table.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [USERS.rows[1]] }
      })
    );
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const verify = Array.from(buttons).find(
      (b) => b.label === "Send verification"
    );
    verify.click();
    await Promise.resolve();

    expect(launchVerification).toHaveBeenCalledWith({
      userIds: ["005000000000002AAA"]
    });
  });

  it("surfaces an Apex error message", async () => {
    getUnverifiedUsers.mockRejectedValue({
      body: { message: "Access denied" }
    });
    const element = createComponent();

    await selectBrand(element);

    expect(element.shadowRoot.textContent).toContain("Access denied");
  });
});
