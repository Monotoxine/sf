/**
 * @author TEKCO Team, 07/04/2026
 * @description Hard block that prevents anonymization from running on a Production org.
 *              Must be called at every entry point (controller + batch start()).
 */
public class TEKCO_AnonymizationSandboxGuard {

    public class ProductionOrgException extends Exception {}

    /**
     * @description Asserts the current org is a sandbox.
     *              Throws ProductionOrgException immediately if IsSandbox is false.
     *              No DML is ever executed if this throws.
     * @throws ProductionOrgException if the running org is not a sandbox.
     */
    public static void assertIsSandbox() {
        Organization org = [
            SELECT IsSandbox
            FROM Organization
            LIMIT 1
        ];
        if (!org.IsSandbox) {
            throw new ProductionOrgException(
                'ABORT: Data anonymization is not allowed on Production orgs. ' +
                'This operation has been blocked. No data was modified.'
            );
        }
    }
}
