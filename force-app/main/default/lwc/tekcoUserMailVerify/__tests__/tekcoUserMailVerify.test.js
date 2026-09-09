import { createElement } from "@lwc/engine-dom";
import TekcoUserMailVerify from "c/tekcoUserMailVerify";
import getBrands from "@salesforce/apex/TEKCO_UserMailVerifyController.getBrands";
import getUsers from "@salesforce/apex/TEKCO_UserMailVerifyController.getUsers";
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
  "@salesforce/apex/TEKCO_UserMailVerifyController.getUsers",
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
      brand: "ACME",
      isVerified: false,
      hasInvalidSuffix: false
    },
    {
      id: "005000000000002AAA",
      name: "Alan Turing",
      username: "alan@example.com",
      email: "alan@example.com.invalid",
      profileName: "Standard User",
      createdDate: "2026-01-02T00:00:00.000Z",
      brand: "GLOBEX",
      isVerified: true,
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

async function selectBrands(element, brands = ["ACME"]) {
  const listbox = element.shadowRoot.querySelector("lightning-dual-listbox");
  listbox.dispatchEvent(
    new CustomEvent("change", { detail: { value: brands } })
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

  it("fills the brand picker from Apex", async () => {
    const element = createComponent();

    getBrands.emit([
      { label: "Acme", value: "ACME" },
      { label: "Globex", value: "GLOBEX" }
    ]);
    await Promise.resolve();

    const listbox = element.shadowRoot.querySelector("lightning-dual-listbox");
    expect(listbox.options).toEqual([
      { label: "Acme", value: "ACME" },
      { label: "Globex", value: "GLOBEX" }
    ]);
  });

  it("hides the reset button outside a sandbox", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrands(element);

    // getSettings never emits here, so isSandbox stays false.
    const labels = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).map((b) => b.label);
    expect(labels).toContain("Verify");
    expect(labels).not.toContain("Verify and reset password");
  });

  it("queries every selected brand at once", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrands(element, ["ACME", "GLOBEX"]);

    expect(getUsers).toHaveBeenCalledWith({
      brands: ["ACME", "GLOBEX"],
      verificationFilter: "UNVERIFIED"
    });
  });

  it("passes the chosen verification status to Apex", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();
    await selectBrands(element);

    const filter = element.shadowRoot.querySelector(
      'lightning-combobox[data-id="verification"]'
    );
    filter.dispatchEvent(
      new CustomEvent("change", { detail: { value: "ALL" } })
    );
    await Promise.resolve();

    // A reset also verifies, so already verified users are legitimate targets.
    expect(getUsers).toHaveBeenLastCalledWith({
      brands: ["ACME"],
      verificationFilter: "ALL"
    });
  });

  it("shows no table before a brand is chosen", () => {
    const element = createComponent();
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
  });

  it("loads users for the selected brand", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrands(element);

    expect(getUsers).toHaveBeenCalledWith({
      brands: ["ACME"],
      verificationFilter: "UNVERIFIED"
    });
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table).not.toBeNull();
    expect(table.data).toHaveLength(2);
  });

  it("links each row to the user record page", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrands(element);

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0].recordUrl).toBe(
      "/lightning/r/User/005000000000001AAA/view"
    );

    const nameColumn = table.columns.find((c) => c.label === "Name");
    expect(nameColumn.type).toBe("url");
    expect(nameColumn.typeAttributes.target).toBe("_blank");
  });

  it("flags addresses carrying the .invalid suffix", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrands(element);

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0].invalidLabel).toBe("");
    expect(table.data[1].invalidLabel).toBe("Yes");
  });

  it("keeps the action buttons disabled until rows are selected", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();

    await selectBrands(element);

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const verify = Array.from(buttons).find((b) => b.label === "Verify");
    expect(verify.disabled).toBe(true);
  });

  it("sends only the selected user ids to Apex", async () => {
    getUsers.mockResolvedValue(USERS);
    launchVerification.mockResolvedValue({
      queuedCount: 1,
      jobId: "707000000000001"
    });
    const element = createComponent();

    await selectBrands(element);

    const table = element.shadowRoot.querySelector("lightning-datatable");
    table.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [USERS.rows[1]] }
      })
    );
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const verify = Array.from(buttons).find((b) => b.label === "Verify");
    verify.click();
    await Promise.resolve();

    expect(launchVerification).toHaveBeenCalledWith({
      userIds: ["005000000000002AAA"]
    });
  });

  it("filters the table on the search term", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();
    await selectBrands(element);

    const search = element.shadowRoot.querySelector(
      'lightning-input[data-id="search"]'
    );
    search.value = "alan";
    search.dispatchEvent(new CustomEvent("change"));
    await Promise.resolve();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data).toHaveLength(1);
    expect(table.data[0].username).toBe("alan@example.com");
  });

  it("keeps a selection made before filtering", async () => {
    getUsers.mockResolvedValue(USERS);
    const element = createComponent();
    await selectBrands(element);

    const table = element.shadowRoot.querySelector("lightning-datatable");
    table.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [USERS.rows[0]] }
      })
    );
    await Promise.resolve();

    // Filter Ada out of view, then select Alan among the visible rows.
    const search = element.shadowRoot.querySelector(
      'lightning-input[data-id="search"]'
    );
    search.value = "alan";
    search.dispatchEvent(new CustomEvent("change"));
    await Promise.resolve();

    table.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [USERS.rows[1]] }
      })
    );
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const verify = Array.from(buttons).find((b) => b.label === "Verify");
    verify.click();
    await Promise.resolve();

    expect(launchVerification).toHaveBeenCalledWith({
      userIds: ["005000000000001AAA", "005000000000002AAA"]
    });
  });

  it("surfaces an Apex error message", async () => {
    getUsers.mockRejectedValue({
      body: { message: "Access denied" }
    });
    const element = createComponent();

    await selectBrands(element);

    expect(element.shadowRoot.textContent).toContain("Access denied");
  });
});
