/**
 * AnonymizationSandboxGuard
 * Hard block: throws exception if running on a Production org.
 * Must be called at every entry point (controller + batch start).
 */
public class AnonymizationSandboxGuard {

    public class ProductionOrgException extends Exception {}

    /**
     * Asserts the current org is a sandbox.
     * Throws ProductionOrgException immediately if IsSandbox == false.
     * No DML is ever executed if this throws.
     */
    public static void assertIsSandbox() {
        Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
        if (!org.IsSandbox) {
            throw new ProductionOrgException(
                'ABORT: Data anonymization is not allowed on Production orgs. ' +
                'This operation has been blocked. No data was modified.'
            );
        }
    }
}
