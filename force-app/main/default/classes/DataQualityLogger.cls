/**
 * @description Advanced logging for Data Quality batch jobs
 * @author Claude
 * @date 2025-10-26
 */
public class DataQualityLogger {

    private static final Integer MAX_LOG_SIZE = 131072; // 128KB limit for long text area
    private static List<LogEntry> logEntries = new List<LogEntry>();
    private static Boolean isEnabled = true;

    public enum LogLevel { DEBUG, INFO, WARN, ERROR }

    /**
     * @description Log entry structure
     */
    public class LogEntry {
        public LogLevel level;
        public String message;
        public String context;
        public Long timestamp;
        public String stackTrace;

        public LogEntry(LogLevel level, String message, String context) {
            this.level = level;
            this.message = message;
            this.context = context;
            this.timestamp = System.currentTimeMillis();
        }

        public String toString() {
            String entry = DateTime.newInstance(timestamp).format('yyyy-MM-dd HH:mm:ss.SSS') +
                          ' [' + level.name() + '] ' +
                          (String.isNotBlank(context) ? '[' + context + '] ' : '') +
                          message;

            if (String.isNotBlank(stackTrace)) {
                entry += '\nStack Trace: ' + stackTrace;
            }

            return entry;
        }
    }

    /**
     * @description Logs a debug message
     */
    public static void debug(String message, String context) {
        log(LogLevel.DEBUG, message, context);
    }

    /**
     * @description Logs an info message
     */
    public static void info(String message, String context) {
        log(LogLevel.INFO, message, context);
    }

    /**
     * @description Logs a warning
     */
    public static void warn(String message, String context) {
        log(LogLevel.WARN, message, context);
    }

    /**
     * @description Logs an error
     */
    public static void error(String message, String context) {
        log(LogLevel.ERROR, message, context);
    }

    /**
     * @description Logs an exception
     */
    public static void error(Exception e, String context) {
        LogEntry entry = new LogEntry(LogLevel.ERROR, e.getMessage(), context);
        entry.stackTrace = e.getStackTraceString();
        logEntries.add(entry);
        System.debug(LoggingLevel.ERROR, entry.toString());
    }

    /**
     * @description Main logging method
     */
    private static void log(LogLevel level, String message, String context) {
        if (!isEnabled) return;

        LogEntry entry = new LogEntry(level, message, context);
        logEntries.add(entry);

        // Also log to System.debug
        LoggingLevel sysLevel = getSystemLogLevel(level);
        System.debug(sysLevel, entry.toString());

        // Keep log size manageable (last 1000 entries)
        if (logEntries.size() > 1000) {
            logEntries.remove(0);
        }
    }

    /**
     * @description Converts our log level to System.LoggingLevel
     */
    private static LoggingLevel getSystemLogLevel(LogLevel level) {
        switch on level {
            when DEBUG { return LoggingLevel.DEBUG; }
            when INFO { return LoggingLevel.INFO; }
            when WARN { return LoggingLevel.WARN; }
            when ERROR { return LoggingLevel.ERROR; }
            when else { return LoggingLevel.DEBUG; }
        }
    }

    /**
     * @description Gets all log entries
     */
    public static List<LogEntry> getEntries() {
        return logEntries;
    }

    /**
     * @description Gets log entries by level
     */
    public static List<LogEntry> getEntriesByLevel(LogLevel level) {
        List<LogEntry> filtered = new List<LogEntry>();
        for (LogEntry entry : logEntries) {
            if (entry.level == level) {
                filtered.add(entry);
            }
        }
        return filtered;
    }

    /**
     * @description Gets all errors
     */
    public static List<LogEntry> getErrors() {
        return getEntriesByLevel(LogLevel.ERROR);
    }

    /**
     * @description Gets formatted log as string
     */
    public static String getFormattedLog() {
        List<String> lines = new List<String>();
        for (LogEntry entry : logEntries) {
            lines.add(entry.toString());
        }
        return String.join(lines, '\n');
    }

    /**
     * @description Clears all logs
     */
    public static void clear() {
        logEntries.clear();
    }

    /**
     * @description Enables/disables logging
     */
    public static void setEnabled(Boolean enabled) {
        isEnabled = enabled;
    }

    /**
     * @description Saves logs to a custom object (if exists)
     * Note: Would require a custom object Data_Quality_Log__c
     */
    public static void persist(String batchId, String ruleName) {
        // This is a placeholder for persisting to a custom object
        // In production, you'd insert records into Data_Quality_Log__c
        String logContent = getFormattedLog();

        if (logContent.length() > MAX_LOG_SIZE) {
            logContent = logContent.substring(0, MAX_LOG_SIZE);
        }

        // Example (would need custom object):
        // Data_Quality_Log__c log = new Data_Quality_Log__c(
        //     Batch_Id__c = batchId,
        //     Rule_Name__c = ruleName,
        //     Log_Content__c = logContent,
        //     Error_Count__c = getErrors().size()
        // );
        // insert log;

        System.debug('Log persisted for batch: ' + batchId + ' | Rule: ' + ruleName);
    }
}
