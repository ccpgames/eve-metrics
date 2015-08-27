
USE ebs_METRICS
GO



-- This creates a few test lookup tables, groups and reports and a data proc that adds random data to the reports
-- Then the data proc is called for 60 days

-- Note that its much easier to add lookup tables, groups and reports using the web ui
-- This is just to get you up and running so there is something visible in the web ui 
-- If you add data directly to these tables when the server is running you need to select Admin - Clear Cache to make it visible in the web ui

-- Note that usually the data procs are called by a nightly job
-- The normal thing is to add a nightly SQL Agent job that does EXEC metric.ExecDataProcs 


--
-- Test lookup tables
--

INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableName, lookupTableIdentifier) VALUES (1, 'Test lookup table 1', 'testLookupTable1')

INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (1, 1, 'Test Lookup Text 1-1')
INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (1, 2, 'Test Lookup Text 1-2')
INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (1, 3, 'Test Lookup Text 1-3')

INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableName, lookupTableIdentifier) VALUES (2, 'Test lookup table 2', 'testLookupTable2')

INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (2, 1, 'Lookup Text 2-1')
INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (2, 2, 'Lookup Text 2-2')
INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (2, 3, 'Lookup Text 2-3')
GO


--
-- Test groups
--

INSERT INTO zmetric.groups (groupID, groupName) VALUES (1, 'Test group 1')
INSERT INTO zmetric.groups (groupID, groupName) VALUES (2, 'Test group 2')
GO


--
-- Test reports
--

INSERT INTO zmetric.counters (groupID, counterID, counterName, counterIdentifier, counterTable, procedureName)
     VALUES (1, 1, 'Test report 1 (simple, single column)', 'testReport1', 'zmetric.keyCounters', 'data.TestReports')

INSERT INTO zmetric.counters (groupID, counterID, counterName, counterIdentifier, counterTable, procedureName)
     VALUES (1, 2, 'Test report 2 (simple, multiple columns)', 'testReport2', 'zmetric.keyCounters', 'data.TestReports')

INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (2, 1, 'Column1')
INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (2, 2, 'Column2')
INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (2, 3, 'Column3')

INSERT INTO zmetric.counters (groupID, counterID, counterName, counterIdentifier, counterTable, keyLookupTableID, keyID, procedureName)
     VALUES (2, 3, 'Test report 3 (lookup, single column)', 'testReport3', 'zmetric.keyCounters', 1, 'lookupID', 'data.TestReports')

INSERT INTO zmetric.counters (groupID, counterID, counterName, counterIdentifier, counterTable, keyLookupTableID, keyID, procedureName)
     VALUES (2, 4, 'Test report 4 (lookup, multiple columns)', 'testReport4', 'zmetric.keyCounters', 2, 'lookupID', 'data.TestReports')

INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (4, 1, 'Column1')
INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (4, 2, 'Column2')
INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (4, 3, 'Column3')

INSERT INTO zsystem.settings ([group], [key], value, [description]) VALUES ('metrics', 'Normalize', 'Test1,Test1 value,1,0,0
Test2,Test2 Column1,2,1,0', '')
GO


--
-- Data proc
--

IF OBJECT_ID('data.TestReports') IS NOT NULL
  DROP PROCEDURE data.TestReports
GO
CREATE PROCEDURE data.TestReports
  @counterDate  date = NULL
AS
    IF @counterDate IS NULL SET @CounterDate = DATEADD(DAY, -1, GETDATE())

    DECLARE @counterID smallint, @lookupTableID int

    SET @counterID = zmetric.Counters_ID('testReport1')
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 0, 0, RAND() * 10000.0)

    SET @counterID = zmetric.Counters_ID('testReport2')
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, 0, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, 0, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, 0, RAND() * 10000.0)

    SET @counterID = zmetric.Counters_ID('testReport3')
    SET @lookupTableID = zsystem.LookupTables_ID('testLookupTable1')
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 0, 1, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 0, 2, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 0, 3, RAND() * 10000.0)

    SET @counterID = zmetric.Counters_ID('testReport4')
    SET @lookupTableID = zsystem.LookupTables_ID('testLookupTable2')
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, 1, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, 1, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, 1, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, 2, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, 2, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, 2, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, 3, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, 3, RAND() * 10000.0)
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, 3, RAND() * 10000.0)
GO



--
-- Execute data proc for 60 days
--

PRINT ''
PRINT 'Adding 60 days of randomm test data...'
SET NOCOUNT ON
DECLARE @counterDate date = DATEADD(day, -1, GETDATE())
WHILE @counterDate >= DATEADD(day, -60, GETDATE())
BEGIN
  PRINT @counterDate
  EXEC zsystem.PrintFlush
  EXEC data.TestReports @counterDate
  SET @counterDate = DATEADD(day, -1, @counterDate)
END
SET NOCOUNT OFF
