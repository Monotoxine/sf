/**
 * @author
 * @description Hard block that prevents anonymization from running on a Production org
 */
public class TEKCO_AnonymizationSandboxGuard {

    public class ProductionOrgException extends Exception {}

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
