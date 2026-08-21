@isTest
private class TEKCO_AnonymizationRunContextTest {

    @isTest
    static void steps_arePoppedInOrderAndSplitBackIntoPhaseAndKey() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, 'Account');
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_CD, 'Case_Attachments');
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_HISTORY, 'Account');

        System.assertEquals(true, ctx.hasSteps(), 'Three steps planned');

        String first = ctx.popStep();
        System.assertEquals('FIELD', TEKCO_AnonymizationRunContext.phaseOf(first), 'Field phase first');
        System.assertEquals('Account', TEKCO_AnonymizationRunContext.keyOf(first), 'On Account');

        System.assertEquals('CD', TEKCO_AnonymizationRunContext.phaseOf(ctx.popStep()),
            'ContentDocument phase second');
        System.assertEquals('HISTORY', TEKCO_AnonymizationRunContext.phaseOf(ctx.popStep()),
            'History phase last');

        System.assertEquals(false, ctx.hasSteps(), 'Plan exhausted');
        System.assertEquals(null, ctx.popStep(), 'Popping an empty plan returns null');
    }

    @isTest
    static void addStep_ignoresBlankDescriptors() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.addStep(null, 'Account');
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, null);
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, '   ');

        System.assertEquals(false, ctx.hasSteps(), 'A blank phase or key plans nothing');
    }

    /** A developer name containing a colon must survive the round trip. */
    @isTest
    static void keyOf_keepsEverythingAfterTheFirstSeparator() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_CD, 'Weird:Name');

        String step = ctx.popStep();
        System.assertEquals('CD', TEKCO_AnonymizationRunContext.phaseOf(step), 'Phase is the prefix');
        System.assertEquals('Weird:Name', TEKCO_AnonymizationRunContext.keyOf(step),
            'The key keeps its own separator');
    }

    @isTest
    static void counters_accumulateAndIgnoreNulls() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.addProcessed(10);
        ctx.addProcessed(5);
        ctx.addProcessed(null);
        ctx.addFailed(2);
        ctx.addDocumentsDeleted(7);
        ctx.addHistoryDeleted(3);

        System.assertEquals(15, ctx.recordsProcessed, 'Processed counts add up across links');
        System.assertEquals(2,  ctx.recordsFailed, 'Failures add up too — they used to be reset');
        System.assertEquals(7,  ctx.documentsDeleted, 'Documents deleted accumulate');
        System.assertEquals(3,  ctx.historyRecordsDeleted, 'History rows deleted accumulate');
    }

    /** A failing run must not grow the serialized payload without bound. */
    @isTest
    static void addErrors_stopsAtTheCeiling() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();

        List<String> flood = new List<String>();
        for (Integer i = 0; i < TEKCO_AnonymizationRunContext.MAX_ACCUMULATED_ERRORS + 50; i++) {
            flood.add('error ' + i);
        }
        ctx.addErrors(flood);
        ctx.addErrors(new List<String>{ 'one more' });
        ctx.addErrors(null);

        System.assertEquals(
            TEKCO_AnonymizationRunContext.MAX_ACCUMULATED_ERRORS, ctx.errors.size(),
            'The error list is capped in one place instead of six'
        );
    }

    @isTest
    static void scopeLookups_returnEmptyRatherThanNull() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();

        System.assertEquals(0, ctx.configDevNamesFor('Account').size(),
            'An unplanned object yields an empty list, never null');
        System.assertEquals(0, ctx.historyConfigDevNamesFor('Account').size(),
            'Same for history config names');
        System.assertEquals(0, ctx.recordIdsFor('Account').size(),
            'Same for By ID scopes');
        System.assertEquals(null, ctx.additionalFilterFor('Account'),
            'A missing additional filter is null, which the query builder drops');
    }

    @isTest
    static void scopeLookups_returnWhatWasPlanned() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.configDevNamesByObject.put('Account', new List<String>{ 'Cfg_A', 'Cfg_B' });
        ctx.historyConfigDevNamesByObject.put('Account', new List<String>{ 'Cfg_A' });
        ctx.additionalFiltersByObject.put('Account', 'IsDeleted = false');
        ctx.recordIdsByObject.put('Account', new List<Id>{ UserInfo.getUserId() });

        System.assertEquals(2, ctx.configDevNamesFor('Account').size(), 'Both configs planned');
        System.assertEquals(1, ctx.historyConfigDevNamesFor('Account').size(), 'One history config');
        System.assertEquals('IsDeleted = false', ctx.additionalFilterFor('Account'), 'Filter kept');
        System.assertEquals(1, ctx.recordIdsFor('Account').size(), 'By ID scope kept');
    }

    /**
     * The context crosses chunk boundaries through Database.Stateful, so it has to survive a
     * serialization round trip with its plan and counters intact.
     */
    @isTest
    static void context_survivesSerialization() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.byId = true;
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, 'Account');
        ctx.addProcessed(12);
        ctx.addErrors(new List<String>{ 'boom' });

        TEKCO_AnonymizationRunContext restored = (TEKCO_AnonymizationRunContext)
            JSON.deserialize(JSON.serialize(ctx), TEKCO_AnonymizationRunContext.class);

        System.assertEquals(true, restored.byId, 'The chain family is preserved');
        System.assertEquals(12, restored.recordsProcessed, 'Counters are preserved');
        System.assertEquals(1, restored.errors.size(), 'Errors are preserved');
        System.assertEquals('FIELD:Account', restored.popStep(), 'The plan is preserved');
    }

    // ─── cap (relocated from TEKCO_AnonymizationBatchUtilsTest) ──────────────────────

    @isTest
    static void cap_truncatesLongStrings() {
        String long400 = 'x'.repeat(400);
        String result  = TEKCO_AnonymizationRunContext.cap(long400);
        System.assertEquals(200, result.length(), 'Capped at 200 characters');
    }

    @isTest
    static void cap_leavesShortStringsAndNullAlone() {
        System.assertEquals('short', TEKCO_AnonymizationRunContext.cap('short'), 'Under the cap');
        System.assertEquals(null, TEKCO_AnonymizationRunContext.cap(null), 'Null passes through');
    }

    // ─── toDevNames ────────────────────────────────────────────────────────────

    // ─── selectedRecordTypes : la selection doit atteindre les requetes ──────────

    /**
     * Elle s arretait au service de lancement, ou elle ne servait qu a ecarter des regles. Une
     * regle couvrant deux populations survivait donc a la selection d une seule, puis etait
     * appliquee aux deux.
     */
    @isTest
    static void selectedRecordTypes_travelWithTheContext() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.selectedRecordTypes = new List<String>{ 'ACCCO_Patient' };

        TEKCO_AnonymizationRunContext restored = (TEKCO_AnonymizationRunContext) JSON.deserialize(
            JSON.serialize(ctx), TEKCO_AnonymizationRunContext.class
        );

        System.assertEquals(1, restored.recordTypeSelection().size(),
            'La selection survit a la serialisation entre deux chunks');
        System.assertEquals('ACCCO_Patient', restored.recordTypeSelection()[0]);
    }

    @isTest
    static void recordTypeSelection_neverReturnsNull() {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        System.assertEquals(0, ctx.recordTypeSelection().size(),
            'Vide par defaut : aucune restriction');

        ctx.selectedRecordTypes = null;
        System.assertEquals(0, ctx.recordTypeSelection().size(),
            'Null est traite comme vide, les appelants passent la valeur telle quelle');
    }
}
