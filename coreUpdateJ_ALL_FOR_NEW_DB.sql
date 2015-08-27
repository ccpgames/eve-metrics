
USE ebs_METRICS
GO



-- ################################################################################################
-- # CORE.J.1                                                                                     #
-- ################################################################################################

---------------------------------------------------------------------------------------------------


IF NOT EXISTS (SELECT * FROM sys.schemas WHERE [name] = 'zsystem')
  EXEC sp_executesql N'CREATE SCHEMA zsystem'
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.settings') IS NULL
BEGIN
  CREATE TABLE zsystem.settings
  (
    [group]        varchar(200)   NOT NULL,
    [key]          varchar(200)   NOT NULL,
    [value]        nvarchar(max)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    defaultValue   nvarchar(max)  NULL,
    critical       bit            NOT NULL  DEFAULT 0,
    allowUpdate    bit            NOT NULL  DEFAULT 0,
    orderID        int            NOT NULL  DEFAULT 0,
    --
    CONSTRAINT settings_PK PRIMARY KEY CLUSTERED ([group], [key])
  )
END
GO


---------------------------------------------------------------------------------------------------

IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Product')
  INSERT INTO zsystem.settings ([group], [key], [value], [description], defaultValue, critical)
       VALUES ('zsystem', 'Product', 'CORE', 'The product being developed (CORE, EVE, WOD, ...)', 'CORE', 1)
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Recipients-Updates')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Recipients-Updates', '', 'Mail recipients for DB update notifications')
GO
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Recipients-Operations')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Recipients-Operations', '', 'Mail recipients for notifications to operations')
GO
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' and [key] = 'Recipients-Operations-Software')
  INSERT INTO zsystem.settings ([group], [key], value, [description])
       VALUES ('zsystem', 'Recipients-Operations-Software', '', 'A recipient list for DB events that should go to both Software and Ops members.')
GO
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Database')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Database', '', 'The database being used.  Often useful to know when working on a restored database with a different name.)')
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.versions') IS NULL
BEGIN
  CREATE TABLE zsystem.versions
  (
    developer       varchar(20)    NOT NULL,
    [version]       int            NOT NULL,
    versionDate     datetime2(2)   NOT NULL,
    userName        nvarchar(100)  NOT NULL,
    loginName       nvarchar(256)  NOT NULL,
    executionCount  int            NOT NULL,
    lastDate        datetime2(2)   NULL,
    lastLoginName   nvarchar(256)  NULL,
    coreVersion     int            NULL,
    firstDuration   int            NULL,
    lastDuration    int            NULL,
    executingSPID   int            NULL
    --
    CONSTRAINT versions_PK PRIMARY KEY CLUSTERED (developer, [version])
  )
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Settings_Value') IS NOT NULL
  DROP FUNCTION zsystem.Settings_Value
GO
CREATE FUNCTION zsystem.Settings_Value(@group varchar(200), @key varchar(200))
RETURNS nvarchar(max)
BEGIN
  DECLARE @value nvarchar(max)
  SELECT @value = LTRIM(RTRIM([value])) FROM zsystem.settings WHERE [group] = @group AND [key] = @key
  RETURN ISNULL(@value, '')
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Start') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Start
GO
CREATE PROCEDURE zsystem.Versions_Start
  @developer  nvarchar(20),
  @version    int,
  @userName   nvarchar(100)
AS
  SET NOCOUNT ON

  DECLARE @currentVersion int
  SELECT @currentVersion = MAX([version]) FROM zsystem.versions WHERE developer = @developer
  IF @currentVersion != @version - 1
  BEGIN
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    PRINT '!!! DATABASE NOT OF CORRECT VERSION !!!'
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  END

  IF NOT EXISTS(SELECT * FROM zsystem.versions WHERE developer = @developer AND [version] = @version)
  BEGIN
    INSERT INTO zsystem.versions (developer, [version], versionDate, userName, loginName, executionCount, executingSPID)
         VALUES (@developer, @version, GETUTCDATE(), @userName, SUSER_SNAME(), 0, @@SPID)
  END
  ELSE
  BEGIN
    UPDATE zsystem.versions 
       SET lastDate = GETUTCDATE(), executingSPID = @@SPID 
     WHERE developer = @developer AND [version] = @version
  END
GO


---------------------------------------------------------------------------------------------------


EXEC zsystem.Versions_Start 'CORE.J', 0001, 'jorundur'
GO


---------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zutil') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zutil'
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.TimeString') IS NOT NULL
  DROP FUNCTION zutil.TimeString
GO
CREATE FUNCTION zutil.TimeString(@seconds int)
RETURNS varchar(20)
BEGIN
  DECLARE @s varchar(20)

  DECLARE @x int

  -- Seconds
  SET @x = @seconds % 60
  SET @s = RIGHT('00' + CONVERT(varchar, @x), 2)
  SET @seconds = @seconds - @x

  -- Minutes
  SET @x = (@seconds % (60 * 60)) / 60
  SET @s = RIGHT('00' + CONVERT(varchar, @x), 2) + ':' + @s
  SET @seconds = @seconds - (@x * 60)

  -- Hours
  SET @x = @seconds / (60 * 60)
  SET @s = CONVERT(varchar, @x) + ':' + @s
  IF LEN(@s) < 8 SET @s = '0' + @s

  RETURN @s
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateDiffString') IS NOT NULL
  DROP FUNCTION zutil.DateDiffString
GO
CREATE FUNCTION zutil.DateDiffString(@dt1 datetime2(0), @dt2 datetime2(0))
RETURNS varchar(20)
BEGIN
  DECLARE @s varchar(20)

  DECLARE @seconds int, @x int
  SET @seconds = ABS(DATEDIFF(second, @dt1, @dt2))

  -- Seconds
  SET @x = @seconds % 60
  SET @s = RIGHT('00' + CONVERT(varchar, @x), 2)
  SET @seconds = @seconds - @x

  -- Minutes
  SET @x = (@seconds % (60 * 60)) / 60
  SET @s = RIGHT('00' + CONVERT(varchar, @x), 2) + ':' + @s
  SET @seconds = @seconds - (@x * 60)

  -- Hours
  SET @x = @seconds / (60 * 60)
  SET @s = CONVERT(varchar, @x) + ':' + @s
  IF LEN(@s) < 8 SET @s = '0' + @s

  RETURN @s
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.SendMail') IS NOT NULL
  DROP PROCEDURE zsystem.SendMail
GO
CREATE PROCEDURE zsystem.SendMail
  @recipients   varchar(max),
  @subject      nvarchar(255),
  @body         nvarchar(max),
  @body_format  varchar(20) = NULL
AS
  SET NOCOUNT ON

  -- Azure does not support msdb.dbo.sp_send_dbmail
  IF CONVERT(varchar(max), SERVERPROPERTY('edition')) NOT LIKE '%Azure%'
  BEGIN
    EXEC sp_executesql N'EXEC msdb.dbo.sp_send_dbmail NULL, @p_recipients, NULL, NULL, @p_subject, @p_body, @p_body_format',
                       N'@p_recipients varchar(max), @p_subject nvarchar(255), @p_body nvarchar(max), @p_body_format  varchar(20)',
                       @p_recipients = @recipients, @p_subject = @subject, @p_body = @body, @p_body_format = @body_format
  END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Finish') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Finish
GO
CREATE PROCEDURE zsystem.Versions_Finish
  @developer  varchar(20),
  @version    int,
  @userName   nvarchar(100)
AS
  SET NOCOUNT ON

  IF EXISTS(SELECT *
              FROM zsystem.versions
             WHERE developer = @developer AND [version] = @version AND userName = @userName AND firstDuration IS NOT NULL)
  BEGIN
    PRINT ''
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    PRINT '!!! DATABASE UPDATE HAS BEEN EXECUTED BEFORE !!!'
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    UPDATE zsystem.versions
       SET executionCount = executionCount + 1, lastDate = GETUTCDATE(),
           lastLoginName = SUSER_SNAME(), lastDuration = DATEDIFF(second, lastDate, GETUTCDATE()), executingSPID = NULL
     WHERE developer = @developer AND [version] = @version
  END
  ELSE
  BEGIN
    DECLARE @coreVersion int
    IF @developer != 'CORE'
      SELECT @coreVersion = MAX([version]) FROM zsystem.versions WHERE developer = 'CORE'

    UPDATE zsystem.versions 
       SET executionCount = executionCount + 1, coreVersion = @coreVersion,
           firstDuration = DATEDIFF(second, versionDate, GETUTCDATE()), executingSPID = NULL
     WHERE developer = @developer AND [version] = @version
  END

  PRINT ''
  PRINT '[EXEC zsystem.Versions_Finish ''' + @developer + ''', ' + CONVERT(varchar, @version) + ', ''' + @userName + '''] has completed'
  PRINT ''

  DECLARE @recipients varchar(max)
  SET @recipients = zsystem.Settings_Value('zsystem', 'Recipients-Updates')
  IF @recipients != '' AND zsystem.Settings_Value('zsystem', 'Database') = DB_NAME()
  BEGIN
    DECLARE @subject nvarchar(255), @body nvarchar(max)
    SET @subject = 'Database update ' + @developer + '-' + CONVERT(varchar, @version) + ' applied on ' + DB_NAME()
    SET @body = NCHAR(13) + @subject + NCHAR(13)
                + NCHAR(13) + '  Developer: ' + @developer
                + NCHAR(13) + '    Version: ' + CONVERT(varchar, @version)
                + NCHAR(13) + '       User: ' + @userName
                + NCHAR(13) + NCHAR(13)
                + NCHAR(13) + '   Database: ' + DB_NAME()
                + NCHAR(13) + '       Host: ' + HOST_NAME()
                + NCHAR(13) + '      Login: ' + SUSER_SNAME()
                + NCHAR(13) + 'Application: ' + APP_NAME()
    EXEC zsystem.SendMail @recipients, @subject, @body
  END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.PrintFlush') IS NOT NULL
  DROP PROCEDURE zsystem.PrintFlush
GO
CREATE PROCEDURE zsystem.PrintFlush
AS
  SET NOCOUNT ON

  BEGIN TRY
    RAISERROR ('', 11, 1) WITH NOWAIT;
  END TRY
  BEGIN CATCH
  END CATCH
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zdm') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zdm'
GO


---------------------------------------------------------------------------------------------------


if not exists(select * from zsystem.settings where [group] = 'zdm' and [key] = 'Recipients-LongRunning')
  insert into zsystem.settings ([group], [key], [value], [description])
       values ('zdm', 'Recipients-LongRunning', '', 'Mail recipients for long running SQL notifications')
go


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.DropDefaultConstraint') IS NOT NULL
  DROP PROCEDURE zdm.DropDefaultConstraint
GO
CREATE PROCEDURE zdm.DropDefaultConstraint
  @tableName   nvarchar(256),
  @columnName  nvarchar(128)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @sql nvarchar(4000)
  SELECT @sql = 'ALTER TABLE ' + @tableName + ' DROP CONSTRAINT ' + OBJECT_NAME(default_object_id)
    FROM sys.columns
   WHERE [object_id] = OBJECT_ID(@tableName) AND [name] = @columnName AND default_object_id != 0
  EXEC (@sql)
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.applocks') IS NOT NULL
  DROP PROCEDURE zdm.applocks
GO
CREATE PROCEDURE zdm.applocks
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT resource_database_id, resource_database_name = DB_NAME(resource_database_id), resource_description,
         request_mode, request_type, request_status, request_reference_count, request_session_id, request_owner_type
    FROM sys.dm_tran_locks
   WHERE resource_type = 'APPLICATION'
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.blockers') IS NOT NULL
  DROP PROCEDURE zdm.blockers
GO
CREATE PROCEDURE zdm.blockers
  @rows  smallint = 30
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @blockingSessionID int

  SELECT TOP 1 @blockingSessionID = blocking_session_id 
    FROM sys.dm_exec_requests 
   WHERE blocking_session_id != 0
   GROUP BY blocking_session_id 
   ORDER BY COUNT(*) DESC

  IF @blockingSessionID > 0
  BEGIN
    SELECT * FROM sys.dm_exec_requests WHERE session_id = @blockingSessionID

    SELECT TOP (@rows) blocking_session_id, blocking_count = COUNT(*)
      FROM sys.dm_exec_requests
     WHERE blocking_session_id != 0
     GROUP BY blocking_session_id
     ORDER BY COUNT(*) DESC
  END
  ELSE
    PRINT 'No blockers found :-)'
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.checkmail') IS NOT NULL
  DROP PROCEDURE zdm.checkmail
GO
CREATE PROCEDURE zdm.checkmail
  @rows  smallint = 10
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC msdb.dbo.sysmail_help_status_sp

  EXEC msdb.dbo.sysmail_help_queue_sp @queue_type = 'mail'

  SELECT TOP (@rows) * FROM msdb.dbo.sysmail_sentitems ORDER BY mailitem_id DESC
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.counters') IS NOT NULL
  DROP PROCEDURE zdm.counters
GO
CREATE PROCEDURE zdm.counters
  @time_to_pass  char(8)= '00:00:03'
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @now datetime2(0), @seconds int, @dbName nvarchar(128),
          @pageLookups bigint, @pageReads bigint, @pageWrites bigint, @pageSplits bigint,
          @transactions bigint, @writeTransactions bigint, @batchRequests bigint,
          @logins bigint, @logouts bigint, @tempTables bigint,
          @indexSearches bigint, @fullScans bigint, @probeScans bigint, @rangeScans bigint

  SELECT @now = GETUTCDATE(), @dbName = DB_NAME()

  SELECT @pageLookups = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Buffer Manager' AND counter_name = 'Page lookups/sec'

  SELECT @pageReads = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Buffer Manager' AND counter_name = 'Page reads/sec'

  SELECT @pageWrites = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Buffer Manager' AND counter_name = 'Page writes/sec'

  SELECT @pageSplits = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Page Splits/sec'

  SELECT @transactions = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Databases' AND counter_name = 'Transactions/sec' AND instance_name = @dbName

  SELECT @writeTransactions = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Databases' AND counter_name = 'Write Transactions/sec' AND instance_name = @dbName

  SELECT @batchRequests = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:SQL Statistics' AND counter_name = 'Batch Requests/sec'

  SELECT @logins = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'Logins/sec'

  SELECT @logouts = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'Logouts/sec'

  SELECT @tempTables = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'Temp Tables Creation Rate'

  SELECT @indexSearches = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Index Searches/sec'

  SELECT @fullScans = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Full Scans/sec'

  SELECT @probeScans = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Probe Scans/sec'

  SELECT @rangeScans = cntr_value
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Range Scans/sec'

  WAITFOR DELAY @time_to_pass

  SET @seconds = DATEDIFF(second, @now, GETUTCDATE())

  SELECT [object_name] = RTRIM([object_name]), counter_name = RTRIM(counter_name), cntr_value = (cntr_value - @pageLookups) / @seconds, info = '', instance_name = RTRIM(instance_name), [description] = 'Number of requests per second to find a page in the buffer pool.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Buffer Manager' AND counter_name = 'Page lookups/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @pageReads) / @seconds, '', RTRIM(instance_name), 'Number of physical database page reads that are issued per second. This statistic displays the total number of physical page reads across all databases. Because physical I/O is expensive, you may be able to minimize the cost, either by using a larger data cache, intelligent indexes, and more efficient queries, or by changing the database design.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Buffer Manager' AND counter_name = 'Page reads/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @pageWrites) / @seconds, '', RTRIM(instance_name), 'Number of physical database page writes issued per second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Buffer Manager' AND counter_name = 'Page writes/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @pageSplits) / @seconds, '', RTRIM(instance_name), 'Number of page splits per second that occur as the result of overflowing index pages.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Page Splits/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), cntr_value, '', RTRIM(instance_name), 'Counts the number of users currently connected to SQL Server.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'User Connections'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), cntr_value, '', RTRIM(instance_name), 'The number of currently active transactions of all types.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Transactions' AND counter_name = 'Transactions'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @transactions) / @seconds, '', RTRIM(instance_name), 'Number of transactions started for the database per second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Databases' AND counter_name = 'Transactions/sec' AND instance_name = @dbName
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @writeTransactions) / @seconds, '', RTRIM(instance_name), 'Number of transactions that wrote to the database and committed, in the last second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Databases' AND counter_name = 'Write Transactions/sec' AND instance_name = @dbName
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), cntr_value, '', RTRIM(instance_name), 'Number of active transactions for the database.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Databases' AND counter_name = 'Active Transactions' AND instance_name = @dbName
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @batchRequests) / @seconds, '', RTRIM(instance_name), 'Number of Transact-SQL command batches received per second. This statistic is affected by all constraints (such as I/O, number of users, cache size, complexity of requests, and so on). High batch requests mean good throughput.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:SQL Statistics' AND counter_name = 'Batch Requests/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @logins) / @seconds, '', RTRIM(instance_name), 'Total number of logins started per second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'Logins/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @logouts) / @seconds, '', RTRIM(instance_name), 'Total number of logout operations started per second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'Logouts/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @tempTables) / @seconds, '', RTRIM(instance_name), 'Number of temporary tables/table variables created per second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:General Statistics' AND counter_name = 'Temp Tables Creation Rate'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @indexSearches) / @seconds, '', RTRIM(instance_name), 'Number of index searches per second. These are used to start a range scan, reposition a range scan, revalidate a scan point, fetch a single index record, and search down the index to locate where to insert a new row.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Index Searches/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @fullScans) / @seconds, '', RTRIM(instance_name), 'Number of unrestricted full scans per second. These can be either base-table or full-index scans.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Full Scans/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @probeScans) / @seconds, '', RTRIM(instance_name), 'Number of probe scans per second that are used to find at most one single qualified row in an index or base table directly.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Probe Scans/sec'
  UNION ALL
  SELECT RTRIM([object_name]), RTRIM(counter_name), (cntr_value - @rangeScans) / @seconds, '', RTRIM(instance_name), 'Number of qualified range scans through indexes per second.'
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Access Methods' AND counter_name = 'Range Scans/sec'
  ORDER BY 5, 1, 2
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.indexinfo') IS NOT NULL
  DROP PROCEDURE zdm.indexinfo
GO
CREATE PROCEDURE zdm.indexinfo
  @tableName  nvarchar(256)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF @tableName IS NOT NULL AND OBJECT_ID(@tableName) IS NULL
  BEGIN
    RAISERROR ('Table not found !!!', 16, 1)
    RETURN -1
  END

  SELECT info = 'avg_fragmentation_in_percent - should be LOW'
  UNION ALL
  SELECT info = 'fragment_count - should be LOW'
  UNION ALL
  SELECT info = 'avg_fragment_size_in_pages - should be HIGH'

  SELECT table_name = t.[name], index_name = i.[name], s.*
    FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(@tableName), NULL, NULL, NULL) s
      LEFT JOIN sys.tables t ON t.[object_id] = s.[object_id]
      LEFT JOIN sys.indexes i ON i.[object_id] = s.[object_id] AND i.index_id = s.index_id
   ORDER BY s.avg_fragmentation_in_percent DESC
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.memory') IS NOT NULL
  DROP PROCEDURE zdm.memory
GO
CREATE PROCEDURE zdm.memory
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT [object_name], counter_name,
         cntr_value = CASE WHEN counter_name LIKE '%(KB)%' THEN CASE WHEN cntr_value > 1048576 THEN CONVERT(varchar, CONVERT(money, cntr_value / 1048576.0)) + ' GB'
                                                                     WHEN cntr_value > 1024 THEN CONVERT(varchar, CONVERT(money, cntr_value / 1024.0)) + ' MB'
                                                                     ELSE CONVERT(varchar, cntr_value) + ' KB' END
                           ELSE CONVERT(varchar, cntr_value) END
    FROM sys.dm_os_performance_counters
   WHERE [object_name] = 'SQLServer:Memory Manager'
   ORDER BY instance_name, [object_name], counter_name
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.plans') IS NOT NULL
  DROP PROCEDURE zdm.plans
GO
CREATE PROCEDURE zdm.plans
  @filter      nvarchar(256),
  @objectType  nvarchar(20) = 'Proc',
  @rows        smallint = 50
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT TOP (@rows) C.objtype, C.cacheobjtype, C.refcounts, C.usecounts, C.size_in_bytes,
         P.query_plan, T.[text]
    FROM sys.dm_exec_cached_plans C
      CROSS APPLY sys.dm_exec_sql_text (C.plan_handle) T
      CROSS APPLY sys.dm_exec_query_plan(C.plan_handle) P
   WHERE C.objtype = @objectType AND T.[text] like N'%' + @filter + N'%'
   ORDER BY C.usecounts DESC
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.plantext') IS NOT NULL
  DROP PROCEDURE zdm.plantext
GO
CREATE PROCEDURE zdm.plantext
  @plan_handle  varbinary(64)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT * FROM sys.dm_exec_query_plan(@plan_handle)
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.procstats') IS NOT NULL
  DROP PROCEDURE zdm.procstats
GO
CREATE PROCEDURE zdm.procstats
  @rows  smallint = 5
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @count float, @CPU float, @reads float, @writes float
  SELECT @count = SUM(execution_count), @CPU = SUM(total_worker_time),
         @reads = SUM(total_logical_reads), @writes = SUM(total_logical_writes)
    FROM sys.dm_exec_procedure_stats

  SELECT TOP (@rows) database_name = DB_NAME(database_id), [object_id],
         [object_name] = OBJECT_SCHEMA_NAME([object_id], database_id) + '.' + OBJECT_NAME([object_id], database_id),
         execution_count,
         PERCENT_EXECUTION_COUNT = ROUND((execution_count / @count) * 100, 2),
         percent_worker_time = ROUND((total_worker_time / @CPU) * 100, 2),
         percent_logical_reads = ROUND((total_logical_reads / @reads) * 100, 2),
         percent_logical_writes = ROUND((total_logical_writes / @writes) * 100, 2),
         last_execution_time = CONVERT(varchar, last_execution_time, 120)
    FROM sys.dm_exec_procedure_stats
   ORDER BY execution_count DESC

  SELECT TOP (@rows) database_name = DB_NAME(database_id), [object_id],
         [object_name] = OBJECT_SCHEMA_NAME([object_id], database_id) + '.' + OBJECT_NAME([object_id], database_id),
         execution_count,
         percent_execution_count = ROUND((execution_count / @count) * 100, 2),
         PERCENT_WORKER_TIME = ROUND((total_worker_time / @CPU) * 100, 2),
         percent_logical_reads = ROUND((total_logical_reads / @reads) * 100, 2),
         percent_logical_writes = ROUND((total_logical_writes / @writes) * 100, 2),
         last_execution_time = CONVERT(varchar, last_execution_time, 120)
    FROM sys.dm_exec_procedure_stats
   ORDER BY total_worker_time DESC

  SELECT TOP (@rows) database_name = DB_NAME(database_id), [object_id],
         [object_name] = OBJECT_SCHEMA_NAME([object_id], database_id) + '.' + OBJECT_NAME([object_id], database_id),
         execution_count,
         percent_execution_count = ROUND((execution_count / @count) * 100, 2),
         percent_worker_time = ROUND((total_worker_time / @CPU) * 100, 2),
         PERCENT_LOGICAL_READS = ROUND((total_logical_reads / @reads) * 100, 2),
         percent_logical_writes = ROUND((total_logical_writes / @writes) * 100, 2),
         last_execution_time = CONVERT(varchar, last_execution_time, 120)
    FROM sys.dm_exec_procedure_stats
   ORDER BY total_logical_reads DESC

  SELECT TOP (@rows) database_name = DB_NAME(database_id), [object_id],
         [object_name] = OBJECT_SCHEMA_NAME([object_id], database_id) + '.' + OBJECT_NAME([object_id], database_id),
         execution_count,
         percent_execution_count = ROUND((execution_count / @count) * 100, 2),
         percent_worker_time = ROUND((total_worker_time / @CPU) * 100, 2),
         percent_logical_reads = ROUND((total_logical_reads / @reads) * 100, 2),
         PERCENT_LOGICAL_WRITES = ROUND((total_logical_writes / @writes) * 100, 2),
         last_execution_time = CONVERT(varchar, last_execution_time, 120)
    FROM sys.dm_exec_procedure_stats
   ORDER BY total_logical_writes DESC
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.sqltext') IS NOT NULL
  DROP PROCEDURE zdm.sqltext
GO
CREATE PROCEDURE zdm.sqltext
  @sql_handle  varbinary(64)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT * FROM sys.dm_exec_sql_text(@sql_handle)
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.stats') IS NOT NULL
  DROP PROCEDURE zdm.stats
GO
CREATE PROCEDURE zdm.stats
  @objectName  nvarchar(256)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF OBJECT_ID(@objectName) IS NULL
  BEGIN
    PRINT 'Object not found!'
    RETURN
  END

  EXEC sp_autostats @objectName

  DECLARE @stmt nvarchar(4000)
  DECLARE @indexName nvarchar(128)

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL STATIC READ_ONLY --FAST_FORWARD
    FOR SELECT name FROM sys.indexes WHERE [object_id] = OBJECT_ID(@objectName) ORDER BY index_id
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @indexName
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @stmt = 'DBCC SHOW_STATISTICS (''' + @objectName + ''', ''' + @indexName + ''')'
    EXEC sp_executesql @stmt

    FETCH NEXT FROM @cursor INTO @indexName
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.tableusage') IS NOT NULL
  DROP PROCEDURE zdm.tableusage
GO
CREATE PROCEDURE zdm.tableusage
  @tableName  nvarchar(256) = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT t.[name], i.[name], s.*
    FROM sys.dm_db_index_usage_stats s
      LEFT JOIN sys.tables t ON t.[object_id] = s.[object_id]
      LEFT JOIN sys.indexes i ON i.[object_id] = s.[object_id] AND i.index_id = s.index_id
   WHERE s.database_id = DB_ID() AND s.[object_id] = OBJECT_ID(@tableName)
   ORDER BY t.name, s.index_id
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.transactions') IS NOT NULL
  DROP PROCEDURE zdm.transactions
GO
CREATE PROCEDURE zdm.transactions
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT [description] = 'All active transactions that have done something...'
  SELECT tat.*, tdt.*
    FROM sys.dm_tran_database_transactions tdt
      LEFT JOIN sys.dm_tran_active_transactions tat ON tat.transaction_id = tdt.transaction_id
   WHERE tdt.database_id = DB_ID()
   ORDER BY tdt.database_transaction_begin_time

  SELECT [description] = 'Active transactions that have done nothing...'
  SELECT *
    FROM sys.dm_tran_active_transactions tat
      LEFT JOIN sys.dm_tran_database_transactions tdt ON tdt.transaction_id = tat.transaction_id
   WHERE tdt.transaction_id IS NULL
   ORDER BY tat.transaction_begin_time
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


-- Code from Itzik Ben-Gan, a very fast inline table function that will return a table of numbers

IF OBJECT_ID('zutil.Numbers') IS NOT NULL
  DROP FUNCTION zutil.Numbers
GO
CREATE FUNCTION zutil.Numbers(@n int)
  RETURNS TABLE
  RETURN WITH L0   AS(SELECT 1 AS c UNION ALL SELECT 1),
              L1   AS(SELECT 1 AS c FROM L0 AS A, L0 AS B),
              L2   AS(SELECT 1 AS c FROM L1 AS A, L1 AS B),
              L3   AS(SELECT 1 AS c FROM L2 AS A, L2 AS B),
              L4   AS(SELECT 1 AS c FROM L3 AS A, L3 AS B),
              L5   AS(SELECT 1 AS c FROM L4 AS A, L4 AS B),
              Nums AS(SELECT ROW_NUMBER() OVER(ORDER BY c) AS n FROM L5)
         SELECT n FROM Nums WHERE n <= @n;
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.Age') IS NOT NULL
  DROP FUNCTION zutil.Age
GO
CREATE FUNCTION zutil.Age(@dob smalldatetime, @today smalldatetime)
RETURNS int
BEGIN
  DECLARE @age int
  SET @age = YEAR(@today) - YEAR(@dob)
  IF MONTH(@today) < MONTH(@dob) SET @age = @age -1
  IF MONTH(@today) = MONTH(@dob) AND DAY(@today) < DAY(@dob) SET @age = @age - 1
  RETURN @age
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.BigintToNvarchar') IS NOT NULL
  DROP FUNCTION zutil.BigintToNvarchar
GO
CREATE FUNCTION zutil.BigintToNvarchar(@bi bigint, @style tinyint)
RETURNS nvarchar(30)
BEGIN
  IF @style = 1
    RETURN PARSENAME(CONVERT(nvarchar, CONVERT(money, @bi), 1), 2)
  RETURN CONVERT(nvarchar, @bi)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.ContainsUnicode') IS NOT NULL
  DROP FUNCTION zutil.ContainsUnicode
GO
CREATE FUNCTION zutil.ContainsUnicode(@s nvarchar(4000))
RETURNS bit
BEGIN
  DECLARE @r bit, @i int, @l int

  SET @r = 0

  IF @s IS NOT NULL
  BEGIN
    SELECT @l = LEN(@s), @i = 1

    WHILE @i <= @l
    BEGIN
      IF UNICODE(SUBSTRING(@s, @i, 1)) > 255
      BEGIN
        SET @r = 1
        BREAK
      END
      SET @i = @i + 1
    END
  END
  
  RETURN @r
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateDay') IS NOT NULL
  DROP FUNCTION zutil.DateDay
GO
CREATE FUNCTION zutil.DateDay(@dt smalldatetime)
RETURNS smalldatetime
BEGIN
  RETURN CONVERT(int, @dt - 0.50000004)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateHour') IS NOT NULL
  DROP FUNCTION zutil.DateHour
GO
CREATE FUNCTION zutil.DateHour(@dt smalldatetime)
RETURNS smalldatetime
BEGIN
  RETURN DATEADD(minute, -DATEPART(minute, @dt), @dt)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateLocal') IS NOT NULL
  DROP FUNCTION zutil.DateLocal
GO
CREATE FUNCTION zutil.DateLocal(@dt smalldatetime)
RETURNS smalldatetime
BEGIN
  RETURN DATEADD(hour, DATEDIFF(hour, GETUTCDATE(), GETDATE()), @dt)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateMonth') IS NOT NULL
  DROP FUNCTION zutil.DateMonth
GO
CREATE FUNCTION zutil.DateMonth(@dt smalldatetime)
RETURNS smalldatetime
BEGIN
  SET @dt = CONVERT(int, @dt - 0.50000004)
  RETURN DATEADD(day, 1 - DATEPART(day, @dt), @dt)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateWeek') IS NOT NULL
  DROP FUNCTION zutil.DateWeek
GO
CREATE FUNCTION zutil.DateWeek(@dt datetime2(0))
RETURNS date
BEGIN
  -- SQL Server says sunday is the first day of the week but the CCP week starts on monday
  SET @dt = CONVERT(date, @dt)
  DECLARE @weekday int = DATEPART(weekday, @dt)
  IF @weekday = 1
    SET @dt = DATEADD(day, -6, @dt)
  ELSE IF @weekday > 2
    SET @dt = DATEADD(day, -(@weekday - 2), @dt)
  RETURN @dt
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DiffFloat') IS NOT NULL
  DROP FUNCTION zutil.DiffFloat
GO
CREATE FUNCTION zutil.DiffFloat(@A float, @B float)
RETURNS bit
BEGIN
  DECLARE @R bit
  IF @A IS NULL AND @B IS NULL
    SET @R = 0
  ELSE
  BEGIN
    IF @A IS NULL OR @B IS NULL
      SET @R = 1
    ELSE IF @A = @B
      SET @R = 0
    ELSE
      SET @R = 1
  END
  RETURN @R
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DiffInt') IS NOT NULL
  DROP FUNCTION zutil.DiffInt
GO
CREATE FUNCTION zutil.DiffInt(@A int, @B int)
RETURNS bit
BEGIN
  DECLARE @R bit
  IF @A IS NULL AND @B IS NULL
    SET @R = 0
  ELSE
  BEGIN
    IF @A IS NULL OR @B IS NULL
      SET @R = 1
    ELSE IF @A = @B
      SET @R = 0
    ELSE
      SET @R = 1
  END
  RETURN @R
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IntToNvarchar') IS NOT NULL
  DROP FUNCTION zutil.IntToNvarchar
GO
CREATE FUNCTION zutil.IntToNvarchar(@i int, @style tinyint)
RETURNS nvarchar(20)
BEGIN
  IF @style = 1
    RETURN PARSENAME(CONVERT(nvarchar, CONVERT(money, @i), 1), 2)
  RETURN CONVERT(nvarchar, @i)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IntToRoman') IS NOT NULL
  DROP FUNCTION zutil.IntToRoman
GO
CREATE FUNCTION zutil.IntToRoman(@intvalue int)
RETURNS varchar(20)
BEGIN
  DECLARE @str varchar(20)
  SET @str = CASE @intvalue
               WHEN 1 THEN 'I'
               WHEN 2 THEN 'II'
               WHEN 3 THEN 'III'
               WHEN 4 THEN 'IV'
               WHEN 5 THEN 'V'
               WHEN 6 THEN 'VI'
               WHEN 7 THEN 'VII'
               WHEN 8 THEN 'VIII'
               WHEN 9 THEN 'IX'
               WHEN 10 THEN 'X'
               WHEN 11 THEN 'XI'
               WHEN 12 THEN 'XII'
               WHEN 13 THEN 'XIII'
               WHEN 14 THEN 'XIV'
               WHEN 15 THEN 'XV'
               WHEN 16 THEN 'XVI'
               WHEN 17 THEN 'XVII'
               WHEN 18 THEN 'XVIII'
               WHEN 19 THEN 'XIX'
               WHEN 20 THEN 'XX'
               WHEN 21 THEN 'XXI'
               WHEN 22 THEN 'XXII'
               WHEN 23 THEN 'XXIII'
               WHEN 24 THEN 'XXIV'
               WHEN 25 THEN 'XXV'
               WHEN 26 THEN 'XXVI'
               WHEN 27 THEN 'XXVII'
               WHEN 28 THEN 'XXVIII'
               WHEN 29 THEN 'XXIX'
               WHEN 30 THEN 'XXX'
               WHEN 31 THEN 'XXXI'
               WHEN 32 THEN 'XXXII'
               WHEN 33 THEN 'XXXIII'
               WHEN 34 THEN 'XXXIV'
               WHEN 35 THEN 'XXXV'
               WHEN 36 THEN 'XXXVI'
               WHEN 37 THEN 'XXXVII'
               WHEN 38 THEN 'XXXVIII'
               WHEN 39 THEN 'XXXIX'
               WHEN 40 THEN 'XL'
               WHEN 41 THEN 'XLI'
               WHEN 42 THEN 'XLII'
               WHEN 43 THEN 'XLIII'
               WHEN 44 THEN 'XLIV'
               WHEN 45 THEN 'XLV'
               WHEN 46 THEN 'XLVI'
               WHEN 47 THEN 'XLVII'
               WHEN 48 THEN 'XLVIII'
               WHEN 49 THEN 'XLIX'
               WHEN 50 THEN 'L'
               WHEN 51 THEN 'LI'
               WHEN 52 THEN 'LII'
               WHEN 53 THEN 'LIII'
               WHEN 54 THEN 'LIV'
               WHEN 55 THEN 'LV'
               WHEN 56 THEN 'LVI'
               WHEN 57 THEN 'LVII'
               WHEN 58 THEN 'LVIII'
               WHEN 59 THEN 'LIX'
               WHEN 60 THEN 'LX'
               ELSE '???'
             END
  RETURN @str
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.MaxFloat') IS NOT NULL
  DROP FUNCTION zutil.MaxFloat
GO
CREATE FUNCTION zutil.MaxFloat(@value1 float, @value2 float)
RETURNS float
BEGIN
  DECLARE @f float
  IF @value1 > @value2
    SET @f = @value1
  ELSE
    SET @f = @value2
  RETURN @f
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.MaxInt') IS NOT NULL
  DROP FUNCTION zutil.MaxInt
GO
CREATE FUNCTION zutil.MaxInt(@value1 int, @value2 int)
RETURNS int
BEGIN
  DECLARE @i int
  IF @value1 > @value2
    SET @i = @value1
  ELSE
    SET @i = @value2
  RETURN @i
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.MoneyToNvarchar') IS NOT NULL
  DROP FUNCTION zutil.MoneyToNvarchar
GO
CREATE FUNCTION zutil.MoneyToNvarchar(@m money, @style tinyint)
RETURNS nvarchar(30)
BEGIN
  IF @style = 1
    RETURN PARSENAME(CONVERT(nvarchar, @m, 1), 2)
  RETURN CONVERT(nvarchar, @m)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.NoBrackets') IS NOT NULL
  DROP FUNCTION zutil.NoBrackets
GO
CREATE FUNCTION zutil.NoBrackets(@s nvarchar(max))
RETURNS nvarchar(max)
BEGIN
  RETURN REPLACE(REPLACE(@s, '[', ''), ']', '')
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.RandomChar') IS NOT NULL
  DROP FUNCTION zutil.RandomChar
GO
CREATE FUNCTION zutil.RandomChar(@charFrom char(1), @charTo char(1), @rand float)
RETURNS char(1)
BEGIN
  DECLARE @cf smallint
  DECLARE @ct smallint
  SET @cf = ASCII(@charFrom)
  SET @ct = ASCII(@charTo)

  DECLARE @c smallint
  SET @c = (@ct - @cf) + 1
  SET @c = @cf + (@c * @rand)
  IF @c > @ct
    SET @c = @ct

  RETURN CHAR(@c)
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.TrimDatetime') IS NOT NULL
  DROP FUNCTION zutil.TrimDatetime
GO
CREATE FUNCTION zutil.TrimDatetime(@value datetime2(0), @minDateTime datetime2(0), @maxDateTime datetime2(0))
RETURNS datetime2(0)
BEGIN
  IF @value < @minDateTime
    RETURN @minDateTime
  IF @value > @maxDateTime
    RETURN @maxDateTime
  RETURN @value
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.UnicodeValueString') IS NOT NULL
  DROP FUNCTION zutil.UnicodeValueString
GO
CREATE FUNCTION zutil.UnicodeValueString(@s nvarchar(200))
RETURNS varchar(2000)
BEGIN
  DECLARE @vs varchar(2000)
  SET @vs = ''
  DECLARE @i int
  DECLARE @len int
  SET @i = 1
  SET @len = LEN(@s)
  WHILE @i <= @len
  BEGIN
    IF @vs != ''
      SET @vs = @vs + '+'
    SET @vs = @vs + 'NCHAR(' + CONVERT(varchar, UNICODE(SUBSTRING(@s, @i, 1))) + ')'
    SET @i = @i + 1
  END
  RETURN @vs
END
GO



---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.ValidIntList') IS NOT NULL
  DROP FUNCTION zutil.ValidIntList
GO
CREATE FUNCTION zutil.ValidIntList(@list varchar(1000))
RETURNS smallint
BEGIN
  DECLARE @len smallint
  DECLARE @pos smallint
  DECLARE @c char(1)
  SET @pos = 1
  SET @len = LEN(@list)
  WHILE @pos <= @len
  BEGIN
    SET @c = SUBSTRING(@list, @pos, 1)
    SET @pos = @pos + 1
    IF ASCII(@c) IN (32, 44) OR ASCII(@c) BETWEEN 48 AND 57
      CONTINUE
    RETURN -1
  END
  RETURN 1
END
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF NOT EXISTS (select * from sys.database_principals where [name] = 'zzp_server')
  CREATE ROLE zzp_server
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


GRANT EXEC ON zutil.Age TO zzp_server
GO
GRANT EXEC ON zutil.BigintToNvarchar TO zzp_server
GO
GRANT EXEC ON zutil.DateDay TO zzp_server
GO
GRANT EXEC ON zutil.DateDiffString TO zzp_server
GO
GRANT EXEC ON zutil.DateHour TO zzp_server
GO
GRANT EXEC ON zutil.DateLocal TO zzp_server
GO
GRANT EXEC ON zutil.DateMonth TO zzp_server
GO
GRANT EXEC ON zutil.DateWeek TO zzp_server
GO
GRANT EXEC ON zutil.IntToNvarchar TO zzp_server
GO
GRANT EXEC ON zutil.MoneyToNvarchar TO zzp_server
GO
GRANT SELECT ON zutil.Numbers TO zzp_server
GO
GRANT EXEC ON zutil.TimeString TO zzp_server
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


GRANT SELECT ON zsystem.settings TO zzp_server
GO

GRANT SELECT ON zsystem.versions TO zzp_server
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.eventTypes') IS NULL
BEGIN
  CREATE TABLE zsystem.eventTypes
  (
    eventTypeID    int            NOT NULL,
    eventTypeName  nvarchar(200)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    obsolete       bit            NOT NULL  DEFAULT 0,
    --
    CONSTRAINT eventTypes_PK PRIMARY KEY CLUSTERED (eventTypeID)
  )
END
GRANT SELECT ON zsystem.eventTypes TO zzp_server
GO


---------------------------------------------------------------------------------------------------


if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000011)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000011, 'Insert', '')
go
if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000012)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000012, 'Update', '')
go
if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000013)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000013, 'Delete', '')
go
if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000014)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000014, 'Copy', '')
go

if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000031)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000031, 'Update system setting', '')
go


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.EventTypes_Select') IS NOT NULL
  DROP PROCEDURE zsystem.EventTypes_Select
GO
CREATE PROCEDURE zsystem.EventTypes_Select
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT eventTypeID, eventTypeName FROM zsystem.eventTypes ORDER BY eventTypeID
GO
GRANT EXEC ON zsystem.EventTypes_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.events') IS NULL
BEGIN
  CREATE TABLE zsystem.events
  (
    eventID      int            NOT NULL IDENTITY(1, 1),
    eventDate    datetime2(0)   NOT NULL DEFAULT GETUTCDATE(),
    eventTypeID  int            NOT NULL,
    duration     int            NULL,
    int_1        int            NULL,
    int_2        int            NULL,
    int_3        int            NULL,
    int_4        int            NULL,
    int_5        int            NULL,
    int_6        int            NULL,
    int_7        int            NULL,
    int_8        int            NULL,
    int_9        int            NULL,
    eventText    nvarchar(max)  NULL,
    referenceID  int            NULL,  -- General referenceID, could f.e. be used for first eventID if there are grouped events
    date_1       date           NULL,
    taskID       int            NULL,  -- Task in zsystem.tasks
    textID       int            NULL,  -- Fixed text in zsystem.texts, displayed as fixedText in zsystem.eventsEx
    nestLevel    tinyint        NULL,  -- @@NESTLEVEL-1 saved by the zsystem.Events_Task* procs, capped at 255
    parentID     int            NULL,  -- General parentID, f.e. to be used for first eventID of the calling proc when nested proc calls
    --
    CONSTRAINT events_PK PRIMARY KEY CLUSTERED (eventID)
  )
END
GRANT SELECT ON zsystem.events TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Settings_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Settings_Select
GO
CREATE PROCEDURE zsystem.Settings_Select
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT [group], [key], [value], critical, allowUpdate, defaultValue, [description], orderID FROM zsystem.settings
  UNION ALL
  SELECT 'zsystem', 'DB_NAME', DB_NAME(), 0, 0, NULL, '', NULL
  ORDER BY 1, 8, 2
GO
GRANT EXEC ON zsystem.Settings_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Select
GO
CREATE PROCEDURE zsystem.Versions_Select
  @developer  varchar(20) = 'CORE'
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT TOP 1 [version], versionDate, userName, coreVersion
    FROM zsystem.versions
   WHERE developer = @developer
   ORDER BY [version] DESC
GO
GRANT EXEC ON zsystem.Versions_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.texts') IS NULL
BEGIN
  CREATE TABLE zsystem.texts
  (
    textID  int                                          NOT NULL  IDENTITY(1, 1),
    [text]  nvarchar(450)  COLLATE Latin1_General_CI_AI  NOT NULL,
    --
    CONSTRAINT texts_PK PRIMARY KEY CLUSTERED (textID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX texts_IX_Text ON zsystem.texts ([text])
END
GRANT SELECT ON zsystem.texts TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Texts_ID') IS NOT NULL
  DROP PROCEDURE zsystem.Texts_ID
GO
CREATE PROCEDURE zsystem.Texts_ID
  @text  nvarchar(450)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF @text IS NULL
    RETURN 0

  DECLARE @textID int
  SELECT @textID = textID FROM zsystem.texts WHERE [text] = @text
  IF @textID IS NULL
  BEGIN
    INSERT INTO zsystem.texts ([text]) VALUES (@text)
    SET @textID = SCOPE_IDENTITY()
  END
  RETURN @textID
GO
GRANT EXEC ON zsystem.Texts_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.schemas') IS NULL
BEGIN
  CREATE TABLE zsystem.schemas
  (
    schemaID       int            NOT NULL,
    schemaName     nvarchar(128)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    webPage        varchar(200)   NULL,
    --
    CONSTRAINT schemas_PK PRIMARY KEY CLUSTERED (schemaID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX schemas_UQ_Name ON zsystem.schemas (schemaName)
END
GRANT SELECT ON zsystem.schemas TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.tables') IS NULL
BEGIN
  CREATE TABLE zsystem.tables
  (
    schemaID             int            NOT NULL,
    tableID              int            NOT NULL,
    tableName            nvarchar(128)  NOT NULL,
    [description]        nvarchar(max)  NOT NULL,
    tableType            varchar(20)    NULL,
    logIdentity          tinyint        NULL,  -- 1:Int, 2:Bigint
    copyStatic           tinyint        NULL,  -- 1:BSD, 2:Regular
    keyID                nvarchar(128)  NULL,
    keyID2               nvarchar(128)  NULL,
    keyID3               nvarchar(128)  NULL,
    sequence             int            NULL,
    keyName              nvarchar(128)  NULL,
    disableEdit          bit            NOT NULL  DEFAULT 0,
    disableDelete        bit            NOT NULL  DEFAULT 0,
    textTableID          int            NULL,
    textKeyID            nvarchar(128)  NULL,
    textTableID2         int            NULL,
    textKeyID2           nvarchar(128)  NULL,
    textTableID3         int            NULL,
    textKeyID3           nvarchar(128)  NULL,
    obsolete             bit            NOT NULL  DEFAULT 0,
    link                 nvarchar(256)  NULL,
    keyDate              nvarchar(128)  NULL,  -- Points to the date column to use for identities (keyID and keyDate used)
    disabledDatasets     bit            NULL,
    revisionOrder        int            NOT NULL  DEFAULT 0,
    denormalized         bit            NOT NULL  DEFAULT 0,  -- Points to a *Dx table and a *Dx_Refresh proc, only one key supported
    keyDateUTC           bit            NOT NULL  DEFAULT 1,  -- States wether the keyDate column is storing UTC or local time (GETUTCDATE or GETDATE)
    --
    CONSTRAINT tables_PK PRIMARY KEY CLUSTERED (tableID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX tables_UQ_Name ON zsystem.tables (schemaID, tableName)
END
GRANT SELECT ON zsystem.tables TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.columns') IS NULL
BEGIN
  CREATE TABLE zsystem.columns
  (
    tableID              int            NOT NULL,
    columnName           nvarchar(128)  NOT NULL,
    --
    [readonly]           bit            NULL,
    --
    lookupTable          nvarchar(128)  NULL,
    lookupID             nvarchar(128)  NULL,
    lookupName           nvarchar(128)  NULL,
    lookupWhere          nvarchar(128)  NULL,
    --
    html                 bit     NULL,
    localizationGroupID  int     NULL,
    obsolete             int     NULL,
    --
    CONSTRAINT columns_PK PRIMARY KEY CLUSTERED (tableID, columnName)
  )
END
GRANT SELECT ON zsystem.columns TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.columnsEx') IS NOT NULL
  DROP VIEW zsystem.columnsEx
GO
CREATE VIEW zsystem.columnsEx
AS
  SELECT T.schemaID, S.schemaName, C.tableID, T.tableName,
         C.columnName, C.[readonly], C.lookupTable, C.lookupID, C.lookupName, C.lookupWhere, C.html
    FROM zsystem.columns C
      LEFT JOIN zsystem.tables T ON T.tableID = C.tableID
        LEFT JOIN zsystem.schemas S ON S.schemaID = T.schemaID
GO
GRANT SELECT ON zsystem.columnsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Schemas_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Schemas_Select
GO
CREATE PROCEDURE zsystem.Schemas_Select
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT * FROM zsystem.schemas
GO
GRANT EXEC ON zsystem.Schemas_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Schemas_Name') IS NOT NULL
  DROP FUNCTION zsystem.Schemas_Name
GO
CREATE FUNCTION zsystem.Schemas_Name(@schemaID int)
RETURNS nvarchar(128)
BEGIN
  DECLARE @schemaName nvarchar(128)
  SELECT @schemaName = schemaName FROM zsystem.schemas WHERE schemaID = @schemaID
  RETURN @schemaName
END
GO
GRANT EXEC ON zsystem.Schemas_Name TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Tables_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Tables_Select
GO
CREATE PROCEDURE zsystem.Tables_Select
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT * FROM zsystem.tables
GO
GRANT EXEC ON zsystem.Tables_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Tables_ID') IS NOT NULL
  DROP FUNCTION zsystem.Tables_ID
GO
CREATE FUNCTION zsystem.Tables_ID(@schemaName nvarchar(128), @tableName nvarchar(128))
RETURNS int
BEGIN
  DECLARE @schemaID int
  SELECT @schemaID = schemaID FROM zsystem.schemas WHERE schemaName = @schemaName

  DECLARE @tableID int
  SELECT @tableID = tableID FROM zsystem.tables WHERE schemaID = @schemaID AND tableName = @tableName
  RETURN @tableID
END
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Tables_Name') IS NOT NULL
  DROP FUNCTION zsystem.Tables_Name
GO
CREATE FUNCTION zsystem.Tables_Name(@tableID int)
RETURNS nvarchar(257)
BEGIN
  DECLARE @fullName nvarchar(257)
  SELECT @fullName = S.schemaName + '.' + T.tableName
    FROM zsystem.tables T
      INNER JOIN zsystem.schemas S ON S.schemaID = T.schemaID
   WHERE T.tableID = @tableID
  RETURN @fullName
END
GO
GRANT EXEC ON zsystem.Tables_Name TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.schemas WHERE schemaID = 2000000001)
  INSERT INTO zsystem.schemas (schemaID, schemaName, [description], webPage)
       VALUES (2000000001, 'zsystem', 'CORE - Zhared system objects, supporting f.e. database version control, meta data about objects, settings, identities, events, jobs and so on.', 'http://core/wiki/DB_zsystem')
GO
IF NOT EXISTS(SELECT * FROM zsystem.schemas WHERE schemaID = 2000000007)
  INSERT INTO zsystem.schemas (schemaID, schemaName, [description], webPage)
       VALUES (2000000007, 'zutil', 'CORE - Utility functions', 'http://core/wiki/DB_zutil')
GO
IF NOT EXISTS(SELECT * FROM zsystem.schemas WHERE schemaID = 2000000008)
  INSERT INTO zsystem.schemas (schemaID, schemaName, [description], webPage)
       VALUES (2000000008, 'zdm', 'CORE - Dynamic Management, procedures to help with SQL Server management (mostly for DBA''s).', 'http://core/wiki/DB_zdm')
GO


IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100001)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description])
       VALUES (2000000001, 2000100001, 'settings', 'Core - Zhared settings stored in DB')
GO
IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100002)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description])
       VALUES (2000000001, 2000100002, 'versions', 'Core - List of DB updates (versions) applied on the DB')
GO
IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100003)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description], copyStatic)
       VALUES (2000000001, 2000100003, 'schemas', 'Core - List of database schemas', 2)
GO
IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100004)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description], copyStatic)
       VALUES (2000000001, 2000100004, 'tables', 'Core - List of database tables', 2)
GO
IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100005)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description], copyStatic)
       VALUES (2000000001, 2000100005, 'columns', 'Core - List of database columns that need special handling', 2)
GO

IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100013)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description], copyStatic)
       VALUES (2000000001, 2000100013, 'eventTypes', 'Core - Events types', 2)
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.identities') IS NULL
BEGIN
  CREATE TABLE zsystem.identities
  (
    tableID           int     NOT NULL,
    identityDate      date    NOT NULL,
    identityInt       int     NULL,
    identityBigInt    bigint  NULL,
    --
    CONSTRAINT identities_PK PRIMARY KEY CLUSTERED (tableID, identityDate)
  )
END
GRANT SELECT ON zsystem.identities TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.identitiesEx') IS NOT NULL
  DROP VIEW zsystem.identitiesEx
GO
CREATE VIEW zsystem.identitiesEx
AS
  SELECT s.schemaName, t.tableName, i.tableID, i.identityDate, i.identityInt, i.identityBigInt
    FROM zsystem.identities i
      LEFT JOIN zsystem.tables t ON t.tableID = i.tableID
        LEFT JOIN zsystem.schemas s ON s.schemaID = t.schemaID
GO
GRANT SELECT ON zsystem.identitiesEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100011)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description])
       VALUES (2000000001, 2000100011, 'identities', 'Core - Identity statistics (used to support searching without the need for datetime indexes)')
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.jobs') IS NULL
BEGIN
  CREATE TABLE zsystem.jobs
  (
    jobID          int            NOT NULL,
    jobName        nvarchar(200)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    [sql]          nvarchar(max)  NOT NULL,
    --
    [hour]         tinyint        NULL,  -- 0, 1, 2, ..., 22, 23
    [minute]       tinyint        NULL,  -- 0, 10, 20, 30, 40, 50
    [day]          tinyint        NULL,  -- 1-7 (day of week, WHERE 1 is sunday and 6 is saturday)
    [week]         tinyint        NULL,  -- 1-4 (week of month)
    --
    [group]        nvarchar(100)  NULL,  -- Typically SCHEDULE or DOWNTIME
    part           smallint       NULL,  -- NULL for SCHEDULE, set for DOWNTIME
    --
    orderID        int            NOT NULL  DEFAULT 0,
    --
    [disabled]     bit            NOT NULL  DEFAULT 0,
    --
    logStarted     bit            NOT NULL  DEFAULT 1,
    logCompleted   bit            NOT NULL  DEFAULT 1,
    --
    CONSTRAINT jobs_PK PRIMARY KEY CLUSTERED (jobID),
    --
    CONSTRAINT jobs_CK_Hour CHECK ([hour] >= 0 AND [hour] <= 23),
    CONSTRAINT jobs_CK_Minute CHECK ([minute] >= 0 AND [minute] <= 50 AND [minute] % 10 = 0),
    CONSTRAINT jobs_CK_Day CHECK ([day] >= 1 AND [day] <= 7),
    CONSTRAINT jobs_CK_Week CHECK ([week] >= 1 AND [week] <= 4),
  )
END
GRANT SELECT ON zsystem.jobs TO zzp_server
GO


---------------------------------------------------------------------------------------------------


if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000021)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000021, 'Job started', '')
go
if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000022)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000022, 'Job info', '')
go
if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000023)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000023, 'Job completed', '')
go
if not exists(select * from zsystem.eventTypes where eventTypeID = 2000000024)
  insert into zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       values (2000000024, 'Job ERROR', '')
go


---------------------------------------------------------------------------------------------------


if not exists(select * from zsystem.jobs where jobID = 2000000001)
  insert into zsystem.jobs (jobID, jobName, [description], [sql], [group], [hour], [minute], orderID)
       values (2000000001, 'CORE - zsystem - Insert identity statistics', '', 'EXEC zsystem.Identities_Insert', 'SCHEDULE', 0, 0, -10)
go
if not exists(select * from zsystem.jobs where jobID = 2000000011)
  insert into zsystem.jobs (jobID, jobName, [description], [sql], [group], [hour], [minute], orderID)
       values (2000000011, 'CORE - zsys - Refresh objects and insert index stats', '', 'EXEC zsys.Objects_Refresh;EXEC zsys.IndexStats_Insert', 'SCHEDULE', 0, 0, -9)
go
if not exists(select * from zsystem.jobs where jobID = 2000000012)
  insert into zsystem.jobs (jobID, jobName, [description], [sql], [group], [hour], [minute], orderID, [disabled])
       values (2000000012, 'CORE - zsys - Index stats DB mail', '', 'EXEC zsys.IndexStats_Mail', 'SCHEDULE', 0, 0, -8, 1)
go
if not exists(select * from zsystem.jobs where jobID = 2000000031)
  insert into zsystem.jobs (jobID, jobName, [description], [sql], [group], [hour], [minute], [day], orderID, [disabled])
       values (2000000031, 'CORE - zsystem - interval overflow alert', '', 'EXEC zsystem.Intervals_OverflowAlert', 'SCHEDULE', 7, 0, 4, -10, 1)
go


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.intervals') IS NULL
BEGIN
  CREATE TABLE zsystem.intervals
  (
    intervalID     int            NOT NULL,
    intervalName   nvarchar(200)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    minID          bigint         NOT NULL,
    maxID          bigint         NOT NULL,
    currentID      bigint         NOT NULL,
    tableID        int            NULL,
    --
    CONSTRAINT intervals_PK PRIMARY KEY CLUSTERED (intervalID)
  )
END
GRANT SELECT ON zsystem.intervals TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Intervals_NextID') IS NOT NULL
  DROP PROCEDURE zsystem.Intervals_NextID
GO
CREATE PROCEDURE zsystem.Intervals_NextID
  @intervalID  int,
  @nextID      bigint OUTPUT
AS
  SET NOCOUNT ON

  UPDATE zsystem.intervals SET @nextID = currentID = currentID + 1 WHERE intervalID = @intervalID
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.lookupTables') IS NULL
BEGIN
  CREATE TABLE zsystem.lookupTables
  (
    lookupTableID             int                                          NOT NULL,
    lookupTableName           nvarchar(200)                                NOT NULL,
    [description]             nvarchar(max)                                NULL,
    --
    schemaID                  int                                          NULL, -- Link lookup table to a schema, just info
    tableID                   int                                          NULL, -- Link lookup table to a table, just info
    [source]                  nvarchar(200)                                NULL, -- Description of data source, f.e. table name
    lookupID                  nvarchar(200)                                NULL, -- Description of lookupID column
    parentID                  nvarchar(200)                                NULL, -- Description of parentID column
    parentLookupTableID       int                                          NULL,
    link                      nvarchar(500)                                NULL, -- If a link to a web page is needed
    lookupTableIdentifier     varchar(500)   COLLATE Latin1_General_CI_AI  NOT NULL, -- Identifier to use in code to make it readable and usable in other Metrics webs
    hidden                    bit                                          NOT NULL  DEFAULT 0,
    obsolete                  bit                                          NOT NULL  DEFAULT 0,
    sourceForID               varchar(20)                                  NULL, -- EXTERNAL/TEXT/MAX
    label                     nvarchar(200)                                NULL, -- If a label is needed instead of lookup text
    --
    CONSTRAINT lookupTables_PK PRIMARY KEY CLUSTERED (lookupTableID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX lookupTables_UQ_Identifier ON zsystem.lookupTables (lookupTableIdentifier)
END
GRANT SELECT ON zsystem.lookupTables TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.lookupValues') IS NULL
BEGIN
  CREATE TABLE zsystem.lookupValues
  (
    lookupTableID  int                                           NOT NULL,
    lookupID       int                                           NOT NULL,
    lookupText     nvarchar(1000)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]  nvarchar(max)                                 NULL,
    parentID       int                                           NULL,
    [fullText]     nvarchar(1000)  COLLATE Latin1_General_CI_AI  NULL,
    --
    CONSTRAINT lookupValues_PK PRIMARY KEY CLUSTERED (lookupTableID, lookupID)
  )
END
GRANT SELECT ON zsystem.lookupValues TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupValues_SelectTable') IS NOT NULL
  DROP PROCEDURE zsystem.LookupValues_SelectTable
GO
CREATE PROCEDURE zsystem.LookupValues_SelectTable
  @lookupTableID  int
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT lookupID, lookupText
    FROM zsystem.lookupValues
   WHERE lookupTableID = @lookupTableID
   ORDER BY lookupID
GO
GRANT EXEC ON zsystem.LookupValues_SelectTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.CatchError') IS NOT NULL
  DROP PROCEDURE zsystem.CatchError
GO
CREATE PROCEDURE zsystem.CatchError
  @objectName  nvarchar(256) = NULL,
  @rollback    bit = 1
AS
  SET NOCOUNT ON

  DECLARE @message nvarchar(4000), @number int, @severity int, @state int, @line int, @procedure nvarchar(200)
  SELECT @number = ERROR_NUMBER(), @severity = ERROR_SEVERITY(), @state = ERROR_STATE(),
         @line = ERROR_LINE(), @procedure = ISNULL(ERROR_PROCEDURE(), '?'), @message = ISNULL(ERROR_MESSAGE(), '?')

  IF @rollback = 1
  BEGIN
    IF @@TRANCOUNT > 0
      ROLLBACK TRANSACTION
  END

  IF @procedure = 'CatchError'
    SET @message = ISNULL(@objectName, '?') + ' >> ' + @message
  ELSE
  BEGIN
    IF @number = 50000
      SET @message = ISNULL(@objectName, @procedure) + ' (line ' + ISNULL(CONVERT(nvarchar, @line), '?') + ') >> ' + @message
    ELSE
    BEGIN
      SET @message = ISNULL(@objectName, @procedure) + ' (line ' + ISNULL(CONVERT(nvarchar, @line), '?')
                   + ', error ' + ISNULL(CONVERT(nvarchar, @number), '?') + ') >> ' + @message
    END
  END

  RAISERROR (@message, @severity, @state)
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.SQL') IS NOT NULL
  DROP PROCEDURE zsystem.SQL
GO
CREATE PROCEDURE zsystem.SQL
  @sql  nvarchar(max)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC sp_executesql @sql
GO
GRANT EXEC ON zsystem.SQL TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.SQLInt') IS NOT NULL
  DROP PROCEDURE zsystem.SQLInt
GO
CREATE PROCEDURE zsystem.SQLInt
  @sqlSelect        nvarchar(500),
  @sqlFrom          nvarchar(500),
  @sqlWhere         nvarchar(500) = NULL,
  @sqlOrder         nvarchar(500) = NULL,
  @parameterName    nvarchar(100),
  @parameterValue   int,
  @comparison       nchar(1) = '='
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @stmt nvarchar(max)
  SET @stmt = 'SELECT ' + @sqlSelect + ' FROM ' + @sqlFrom + ' WHERE '
  IF NOT (@sqlWhere IS NULL OR @sqlWhere = '')
    SET @stmt = @stmt + @sqlWhere + ' AND '
  SET @stmt = @stmt + @parameterName + ' ' + @comparison + ' @pParameterValue'
  IF NOT (@sqlOrder IS NULL OR @sqlOrder = '')
    SET @stmt = @stmt + ' ORDER BY ' + @sqlOrder
  EXEC sp_executesql @stmt, N'@pParameterValue int', @pParameterValue = @parameterValue
GO
GRANT EXEC ON zsystem.SQLInt TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.SQLBigInt') IS NOT NULL
  DROP PROCEDURE zsystem.SQLBigInt
GO
CREATE PROCEDURE zsystem.SQLBigInt
  @sqlSelect        nvarchar(500),
  @sqlFrom          nvarchar(500),
  @sqlWhere         nvarchar(500) = NULL,
  @sqlOrder         nvarchar(500) = NULL,
  @parameterName    nvarchar(100),
  @parameterValue   bigint,
  @comparison       nchar(1) = '='
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @stmt nvarchar(max)
  SET @stmt = 'SELECT ' + @sqlSelect + ' FROM ' + @sqlFrom + ' WHERE '
  IF NOT (@sqlWhere IS NULL OR @sqlWhere = '')
    SET @stmt = @stmt + @sqlWhere + ' AND '
  SET @stmt = @stmt + @parameterName + ' ' + @comparison + ' @pParameterValue'
  IF NOT (@sqlOrder IS NULL OR @sqlOrder = '')
    SET @stmt = @stmt + ' ORDER BY ' + @sqlOrder
  EXEC sp_executesql @stmt, N'@pParameterValue bigint', @pParameterValue = @parameterValue
GO
GRANT EXEC ON zsystem.SQLBigInt TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.SQLSELECT') IS NOT NULL
  DROP PROCEDURE zsystem.SQLSELECT
GO
CREATE PROCEDURE zsystem.SQLSELECT
  @sql  nvarchar(max)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SET ROWCOUNT 1000

  BEGIN TRY
    IF CHARINDEX(';', @sql) > 0
      RAISERROR ('Semicolon in SQL', 13, 1)

    DECLARE @usql nvarchar(4000)
    SET @usql = UPPER(@sql)

    IF NOT @usql LIKE 'SELECT %'
      RAISERROR ('SQL must start with SELECT ', 13, 1)

    IF CHARINDEX('INSERT', @usql) > 0
      RAISERROR ('INSERT in SQL', 13, 1)

    IF CHARINDEX('INTO', @usql) > 0
      RAISERROR ('INTO in SQL', 13, 1)

    IF CHARINDEX('UPDATE', @usql) > 0
      RAISERROR ('UPDATE in SQL', 13, 1)

    IF CHARINDEX('DELETE', @usql) > 0
      RAISERROR ('DELETE in SQL', 13, 1)

    IF CHARINDEX('TRUNCATE', @usql) > 0
      RAISERROR ('TRUNCATE in SQL', 13, 1)

    IF CHARINDEX('CREATE', @usql) > 0
      RAISERROR ('CREATE in SQL', 13, 1)

    IF CHARINDEX('ALTER', @usql) > 0
      RAISERROR ('ALTER in SQL', 13, 1)

    IF CHARINDEX('DROP', @usql) > 0
      RAISERROR ('DROP in SQL', 13, 1)

    IF CHARINDEX('EXEC', @usql) > 0
      RAISERROR ('EXEC in SQL', 13, 1)

    EXEC sp_executesql @sql
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zsystem.SQLSELECT'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zsystem.SQLSELECT TO zzp_server
GO


---------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0001, 'jorundur'
GO






-- ################################################################################################
-- # CORE.J.2                                                                                     #
-- ################################################################################################

EXEC zsystem.Versions_Start 'CORE.J', 0002, 'jorundur'
GO



---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.PrintNow') IS NOT NULL
  DROP PROCEDURE zsystem.PrintNow
GO
CREATE PROCEDURE zsystem.PrintNow
  @str        nvarchar(4000),
  @printTime  bit = 0
AS
  SET NOCOUNT ON

  IF @printTime = 1
    SET @str = CONVERT(nvarchar, GETUTCDATE(), 120) + ' : ' + @str

  RAISERROR (@str, 0, 1) WITH NOWAIT;
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zdm' AND [key] = 'LongRunning-IgnoreSQL')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zdm', 'LongRunning-IgnoreSQL', '%--DBA%', 'Ignore SQL in long running SQL notifications.  Comma delimited list things to use in NOT LIKE.')
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.RebuildDependencies') IS NOT NULL
  DROP PROCEDURE zdm.RebuildDependencies
GO
CREATE PROCEDURE zdm.RebuildDependencies
  @listAllObjects  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @objectName nvarchar(500), @typeName nvarchar(60)

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT QUOTENAME(S.name) + '.' + QUOTENAME(O.name), O.type_desc
          FROM sys.objects O
            INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
         WHERE O.is_ms_shipped = 0 AND O.[type] IN ('FN', 'IF', 'P', 'V')
         ORDER BY O.[type], S.name, O.name
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @objectName, @typeName
  WHILE @@FETCH_STATUS = 0
  BEGIN
    IF @listAllObjects = 1
      PRINT @typeName + ' : ' + @objectName

    BEGIN TRY
      EXEC sp_refreshsqlmodule @objectName
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION
      IF @listAllObjects = 0
        PRINT @typeName + ' : ' + @objectName
      PRINT '  ' + ERROR_MESSAGE()
    END CATCH

    FETCH NEXT FROM @cursor INTO @objectName, @typeName
  END
  CLOSE @cursor
  DEALLOCATE @cursor

  SET NOCOUNT OFF 
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.stats') IS NOT NULL
  DROP PROCEDURE zdm.stats
GO
CREATE PROCEDURE zdm.stats
  @objectName  nvarchar(256)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF OBJECT_ID(@objectName) IS NULL
  BEGIN
    PRINT 'Object not found!'
    RETURN
  END

  EXEC sp_autostats @objectName

  DECLARE @stmt nvarchar(4000)
  DECLARE @indexName nvarchar(128)

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT name FROM sys.indexes WHERE [object_id] = OBJECT_ID(@objectName) ORDER BY index_id
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @indexName
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @stmt = 'DBCC SHOW_STATISTICS (''' + @objectName + ''', ''' + @indexName + ''')'
    EXEC sp_executesql @stmt

    FETCH NEXT FROM @cursor INTO @indexName
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.Age') IS NOT NULL
  DROP FUNCTION zutil.Age
GO
CREATE FUNCTION zutil.Age(@dob datetime2(0), @today datetime2(0))
RETURNS int
BEGIN
  DECLARE @age int
  SET @age = YEAR(@today) - YEAR(@dob)
  IF MONTH(@today) < MONTH(@dob) SET @age = @age -1
  IF MONTH(@today) = MONTH(@dob) AND DAY(@today) < DAY(@dob) SET @age = @age - 1
  RETURN @age
END
GO
GRANT EXEC ON zutil.Age TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateDay') IS NOT NULL
  DROP FUNCTION zutil.DateDay
GO
CREATE FUNCTION zutil.DateDay(@dt datetime2(0))
RETURNS date
BEGIN
  RETURN CONVERT(date, @dt)
END
GO
GRANT EXEC ON zutil.DateDay TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateHour') IS NOT NULL
  DROP FUNCTION zutil.DateHour
GO
CREATE FUNCTION zutil.DateHour(@dt datetime2(0))
RETURNS datetime2(0)
BEGIN
  SET @dt = DATEADD(second, -DATEPART(second, @dt), @dt)
  RETURN DATEADD(minute, -DATEPART(minute, @dt), @dt)
END
GO
GRANT EXEC ON zutil.DateHour TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateLocal') IS NOT NULL
  DROP FUNCTION zutil.DateLocal
GO
CREATE FUNCTION zutil.DateLocal(@dt datetime2(0))
RETURNS datetime2(0)
BEGIN
  RETURN DATEADD(hour, DATEDIFF(hour, GETUTCDATE(), GETDATE()), @dt)
END
GO
GRANT EXEC ON zutil.DateLocal TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateMinute') IS NOT NULL
  DROP FUNCTION zutil.DateMinute
GO
CREATE FUNCTION zutil.DateMinute(@dt datetime2(0))
RETURNS datetime2(0)
BEGIN
  RETURN DATEADD(second, -DATEPART(second, @dt), @dt)
END
GO
GRANT EXEC ON zutil.DateMinute TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateMonth') IS NOT NULL
  DROP FUNCTION zutil.DateMonth
GO
CREATE FUNCTION zutil.DateMonth(@dt datetime2(0))
RETURNS date
BEGIN
  SET @dt = CONVERT(date, @dt)
  RETURN DATEADD(day, 1 - DATEPART(day, @dt), @dt)
END
GO
GRANT EXEC ON zutil.DateMonth TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateTimeDay') IS NOT NULL
  DROP FUNCTION zutil.DateTimeDay
GO
CREATE FUNCTION zutil.DateTimeDay(@dt datetime2(0))
RETURNS datetime2(0)
BEGIN
  RETURN CONVERT(date, @dt)
END
GO
GRANT EXEC ON zutil.DateTimeDay TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateXMinutes') IS NOT NULL
  DROP FUNCTION zutil.DateXMinutes
GO
CREATE FUNCTION zutil.DateXMinutes(@dt datetime2(0), @minutes tinyint)
RETURNS datetime2(0)
BEGIN
  SET @dt = DATEADD(second, -DATEPART(second, @dt), @dt)
  RETURN DATEADD(minute, -(DATEPART(minute, @dt) % @minutes), @dt)
END
GO
GRANT EXEC ON zutil.DateXMinutes TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateYear') IS NOT NULL
  DROP FUNCTION zutil.DateYear
GO
CREATE FUNCTION zutil.DateYear(@dt datetime2(0))
RETURNS date
BEGIN
  SET @dt = CONVERT(date, @dt)
  RETURN DATEADD(day, 1 - DATEPART(dayofyear, @dt), @dt)
END
GO
GRANT EXEC ON zutil.DateYear TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.InitCap') IS NOT NULL
  DROP FUNCTION zutil.InitCap
GO
CREATE FUNCTION zutil.InitCap(@s nvarchar(4000)) 
RETURNS nvarchar(4000)
AS
BEGIN
  DECLARE @i int, @char nchar(1), @prevChar nchar(1), @output nvarchar(4000)

  SELECT @output = LOWER(@s), @i = 1

  WHILE @i <= LEN(@s)
  BEGIN
    SELECT @char = SUBSTRING(@s, @i, 1),
           @prevChar = CASE WHEN @i = 1 THEN ' ' ELSE SUBSTRING(@s, @i - 1, 1) END

    IF @prevChar IN (' ', ';', ':', '!', '?', ',', '.', '_', '-', '/', '&', '''', '(')
    BEGIN
      IF @prevChar != '''' OR UPPER(@char) != 'S'
        SET @output = STUFF(@output, @i, 1, UPPER(@char))
    END

    SET @i = @i + 1
  END

  RETURN @output
END
GO
GRANT EXEC ON zutil.InitCap TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.WordCount') IS NOT NULL
  DROP FUNCTION zutil.WordCount
GO
CREATE FUNCTION zutil.WordCount(@s nvarchar(max))
RETURNS int
BEGIN
  -- Returns the word count of a string
  -- Note that the function does not return 100% correct value if the string has over 10 whitespaces in a row
  SET @s = REPLACE(@s, CHAR(10), ' ')
  SET @s = REPLACE(@s, CHAR(13), ' ')
  SET @s = REPLACE(@s, CHAR(9), ' ')
  SET @s = REPLACE(@s, '    ', ' ')
  SET @s = REPLACE(@s, '   ', ' ')
  SET @s = REPLACE(@s, '  ', ' ')
  SET @s = LTRIM(@s)
  IF @s = ''
    RETURN 0
  RETURN LEN(@s) - LEN(REPLACE(@s, ' ', '')) + 1
END
GO
GRANT EXEC ON zutil.WordCount TO zzp_server
GO


---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000000001)
  INSERT INTO zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000000001, 'Procedure started', '')
IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000000002)
  INSERT INTO  zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000000002, 'Procedure info', '')
GO
IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000000003)
  INSERT INTO  zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000000003, 'Procedure completed', '')
GO
IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000000004)
  INSERT INTO  zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000000004, 'Procedure ERROR', '')
GO


---------------------------------------------------------------------------------------------------


UPDATE zsystem.tables SET [description] = 'Core - System - Shared settings stored in DB' WHERE tableID = 2000100001
GO
UPDATE zsystem.tables SET [description] = 'Core - System - List of DB updates (versions) applied on the DB' WHERE tableID = 2000100002
GO
UPDATE zsystem.tables SET [description] = 'Core - System - List of database schemas' WHERE tableID = 2000100003
GO
UPDATE zsystem.tables SET [description] = 'Core - System - List of database tables' WHERE tableID = 2000100004
GO
UPDATE zsystem.tables SET [description] = 'Core - System - List of database columns that need special handling' WHERE tableID = 2000100005
GO
UPDATE zsystem.tables SET [description] = 'Core - System - Identity statistics (used to support searching without the need for datetime indexes)' WHERE tableID = 2000100011
GO
UPDATE zsystem.tables SET [description] = 'Core - System - Events types' WHERE tableID = 2000100013
GO


---------------------------------------------------------------------------------------------------


update zsystem.tables set copyStatic = null where tableID = 2000100003 and tableName = 'schemas' and copyStatic is not null
update zsystem.tables set copyStatic = null where tableID = 2000100004 and tableName = 'tables' and copyStatic is not null
update zsystem.tables set copyStatic = null where tableID = 2000100005 and tableName = 'columns' and copyStatic is not null
go


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.columnsEx') IS NOT NULL
  DROP VIEW zsystem.columnsEx
GO
CREATE VIEW zsystem.columnsEx
AS
  SELECT T.schemaID, S.schemaName, C.tableID, T.tableName,
         C.columnName, C.[readonly], C.lookupTable, C.lookupID, C.lookupName,
         C.lookupWhere, C.html, C.localizationGroupID, C.obsolete
    FROM zsystem.columns C
      LEFT JOIN zsystem.tables T ON T.tableID = C.tableID
        LEFT JOIN zsystem.schemas S ON S.schemaID = T.schemaID
GO
GRANT SELECT ON zsystem.columnsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupValues_SelectTable') IS NOT NULL
  DROP PROCEDURE zsystem.LookupValues_SelectTable
GO
CREATE PROCEDURE zsystem.LookupValues_SelectTable
  @lookupTableID  int
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT lookupID, lookupText, parentID
    FROM zsystem.lookupValues
   WHERE lookupTableID = @lookupTableID
   ORDER BY lookupID
GO
GRANT EXEC ON zsystem.LookupValues_SelectTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0002, 'jorundur'
GO






-- ################################################################################################
-- # CORE.J.3                                                                                     #
-- ################################################################################################

EXEC zsystem.Versions_Start 'CORE.J', 0003, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_FirstExecution') IS NOT NULL
  DROP FUNCTION zsystem.Versions_FirstExecution
GO
CREATE FUNCTION zsystem.Versions_FirstExecution()
RETURNS bit
BEGIN
  IF EXISTS(SELECT * FROM zsystem.versions WHERE executingSPID = @@SPID AND firstDuration IS NULL)
    RETURN 1
  RETURN 0
END
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateMinutes') IS NOT NULL
  DROP FUNCTION zutil.DateMinutes
GO
CREATE FUNCTION zutil.DateMinutes(@dt datetime2(0), @minutes tinyint)
RETURNS datetime2(0)
BEGIN
  SET @dt = DATEADD(second, -DATEPART(second, @dt), @dt)
  RETURN DATEADD(minute, -(DATEPART(minute, @dt) % @minutes), @dt)
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.SplitMask') IS NOT NULL
  DROP FUNCTION zutil.SplitMask
GO
CREATE FUNCTION zutil.SplitMask(@bitMask bigint)
  RETURNS TABLE
  RETURN SELECT [bit] = POWER(CONVERT(bigint, 2), n - 1) FROM zutil.Numbers(63) WHERE @bitMask & POWER(CONVERT(bigint, 2), n - 1) > 0
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateXMinutes') IS NOT NULL
  DROP FUNCTION zutil.DateXMinutes
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


GRANT EXEC ON zutil.DateMinutes TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000000032)
  INSERT INTO zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000000032, 'Insert system setting', '')
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


UPDATE zsystem.jobs SET jobName = 'CORE - zmetric - Save stats', [sql] = 'EXEC zmetric.ColumnCounters_SaveStats' WHERE jobID = 2000000011
UPDATE zsystem.jobs SET jobName = 'CORE - zmetric - Index stats DB mail', [sql] = 'EXEC zmetric.IndexStats_Mail' WHERE jobID = 2000000012
UPDATE zsystem.jobs SET jobName = 'CORE - zsystem - Interval overflow alert' WHERE jobID = 2000000031
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.jobsEx') IS NOT NULL
  DROP VIEW zsystem.jobsEx
GO
CREATE VIEW zsystem.jobsEx
AS
  SELECT jobID, jobName, [description], [sql], [hour], [minute],
         [time] = CASE WHEN part IS NOT NULL THEN NULL
                       WHEN [week] IS NULL AND [day] IS NULL AND [hour] IS NULL AND [minute] IS NULL THEN 'XX:X0'
                       WHEN [week] IS NULL AND [day] IS NULL AND [hour] IS NULL THEN 'XX:' + RIGHT('0' + CONVERT(varchar, [minute]), 2)
                       ELSE RIGHT('0' + CONVERT(varchar, [hour]), 2) + ':' + RIGHT('0' + CONVERT(varchar, [minute]), 2) END,
         [day], dayText = CASE [day] WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday'
                                     WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday'
                                     WHEN 7 THEN 'Saturday' END,
         [week], weekText = CASE [week] WHEN 1 THEN 'First (days 1-7 of month)'
                                        WHEN 2 THEN 'Second (days 8-14 of month)'
                                        WHEN 3 THEN 'Third (days 15-21 of month)'
                                        WHEN 4 THEN 'Fourth (days 22-28 of month)' END,
         [group], part, logStarted, logCompleted, orderID, [disabled]
    FROM zsystem.jobs
GO
GRANT SELECT ON zsystem.jobsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Tables_ID') IS NOT NULL
  DROP FUNCTION zsystem.Tables_ID
GO
CREATE FUNCTION zsystem.Tables_ID(@schemaName nvarchar(128), @tableName nvarchar(128))
RETURNS int
BEGIN
  DECLARE @schemaID int
  SELECT @schemaID = schemaID FROM zsystem.schemas WHERE schemaName = @schemaName

  DECLARE @tableID int
  SELECT @tableID = tableID FROM zsystem.tables WHERE schemaID = @schemaID AND tableName = @tableName
  RETURN @tableID
END
GO
GRANT EXEC ON zsystem.Tables_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Table_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Table_Select
GO
CREATE PROCEDURE zsystem.Table_Select
  @schemaName    nvarchar(128),
  @tableName     nvarchar(128)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    DECLARE @sql nvarchar(4000)
    SET @sql = ''
    SELECT @sql = @sql + ', ' + QUOTENAME(name)
      FROM sys.columns
     WHERE [object_id] = OBJECT_ID(@schemaName + '.' + @tableName)
     ORDER BY column_id
    SET @sql = 'SELECT ' + SUBSTRING(@sql, 3, 4000) + ' FROM ' + QUOTENAME(@schemaName) + '.' + QUOTENAME(@tableName) + ' ORDER BY 1'
    EXEC sp_executesql @sql
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zsystem.Table_Select'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Identities_Check') IS NOT NULL
  DROP PROCEDURE zsystem.Identities_Check
GO
CREATE PROCEDURE zsystem.Identities_Check
  @schemaName  nvarchar(128),
  @tableName   nvarchar(128),
  @rows        smallint = 100
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @schemaID int
  SELECT @schemaID = schemaID FROM zsystem.schemas WHERE schemaName = @schemaName

  DECLARE @tableID int
  SELECT @tableID = tableID FROM zsystem.tables WHERE schemaID = @schemaID AND tableName = @tableName

  SELECT TOP (@rows) tableID, identityDate, identityInt, identityBigInt
    FROM zsystem.identities
   WHERE tableID = @tableID
   ORDER BY identityDate DESC
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Identities_BigInt') IS NOT NULL
  DROP FUNCTION zsystem.Identities_BigInt
GO
CREATE FUNCTION zsystem.Identities_BigInt(@tableID int, @identityDate date, @days smallint, @seek smallint)
  RETURNS bigint
BEGIN
  IF @identityDate IS NULL SET @identityDate = GETUTCDATE()
  IF @days IS NOT NULL SET @identityDate = DATEADD(day, @days, @identityDate)

  DECLARE @identityBigInt bigint

  IF @seek < 0
  BEGIN
    SELECT TOP 1 @identityBigInt = identityBigInt
      FROM zsystem.identities
     WHERE tableID = @tableID AND identityDate <= @identityDate
     ORDER BY identityDate DESC
  END
  ELSE IF @seek > 0
  BEGIN
    SELECT TOP 1 @identityBigInt = identityBigInt
      FROM zsystem.identities
     WHERE tableID = @tableID AND identityDate >= @identityDate
     ORDER BY identityDate
  END
  ELSE
  BEGIN
    SELECT @identityBigInt = identityBigInt
      FROM zsystem.identities
     WHERE tableID = @tableID AND identityDate = @identityDate
  END

  RETURN ISNULL(@identityBigInt, -1)
END
GO
GRANT EXEC ON zsystem.Identities_BigInt TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Identities_Int') IS NOT NULL
  DROP FUNCTION zsystem.Identities_Int
GO
CREATE FUNCTION zsystem.Identities_Int(@tableID int, @identityDate date, @days smallint, @seek smallint)
  RETURNS int
BEGIN
  IF @identityDate IS NULL SET @identityDate = GETUTCDATE()
  IF @days IS NOT NULL SET @identityDate = DATEADD(day, @days, @identityDate)

  DECLARE @identityInt int

  IF @seek < 0
  BEGIN
    SELECT TOP 1 @identityInt = identityInt
      FROM zsystem.identities
     WHERE tableID = @tableID AND identityDate <= @identityDate
     ORDER BY identityDate DESC
  END
  ELSE IF @seek > 0
  BEGIN
    SELECT TOP 1 @identityInt = identityInt
      FROM zsystem.identities
     WHERE tableID = @tableID AND identityDate >= @identityDate
     ORDER BY identityDate
  END
  ELSE
  BEGIN
    SELECT @identityInt = identityInt
      FROM zsystem.identities
     WHERE tableID = @tableID AND identityDate = @identityDate
  END

  RETURN ISNULL(@identityInt, -1)
END
GO
GRANT EXEC ON zsystem.Identities_Int TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000001)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableName, lookupTableIdentifier) VALUES (2000000001, 'DB Metrics - Procedure names', 'core.db.procs')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000005)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableName, lookupTableIdentifier) VALUES (2000000005, 'DB Metrics - Index names', 'core.db.indexes')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000006)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableName, lookupTableIdentifier) VALUES (2000000006, 'DB Metrics - Table names', 'core.db.tables')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000007)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableName, lookupTableIdentifier) VALUES (2000000007, 'DB Metrics - File stats', 'core.db.filegroups')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupTables_ID') IS NOT NULL
  DROP FUNCTION zsystem.LookupTables_ID
GO
CREATE FUNCTION zsystem.LookupTables_ID(@lookupTableIdentifier varchar(500))
RETURNS int
BEGIN
  DECLARE @lookupTableID int
  SELECT @lookupTableID = lookupTableID FROM zsystem.lookupTables WHERE lookupTableIdentifier = @lookupTableIdentifier
  RETURN @lookupTableID
END
GO
GRANT EXEC ON zsystem.LookupTables_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.lookupValuesEx') IS NOT NULL
  DROP VIEW zsystem.lookupValuesEx
GO
CREATE VIEW zsystem.lookupValuesEx
AS
  SELECT V.lookupTableID, T.lookupTableName, V.lookupID, V.lookupText, V.[fullText], V.parentID, V.[description]
    FROM zsystem.lookupValues V
      LEFT JOIN zsystem.lookupTables T ON T.lookupTableID = V.lookupTableID
GO
GRANT SELECT ON zsystem.lookupValuesEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupValues_Update') IS NOT NULL
  DROP PROCEDURE zsystem.LookupValues_Update
GO
CREATE PROCEDURE zsystem.LookupValues_Update
  @lookupTableID  int,
  @lookupID       int, -- If NULL then zsystem.Texts_ID is used
  @lookupText     nvarchar(1000)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @lookupID IS NULL
    BEGIN
      IF LEN(@lookupText) > 450
        RAISERROR ('@lookupText must not be over 450 characters if zsystem.Texts_ID is used', 16, 1)
      EXEC @lookupID = zsystem.Texts_ID @lookupText
    END

    IF EXISTS(SELECT * FROM zsystem.lookupValues WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID)
      UPDATE zsystem.lookupValues SET lookupText = @lookupText WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID AND lookupText != @lookupText
    ELSE
      INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (@lookupTableID, @lookupID, @lookupText)

    RETURN @lookupID
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zsystem.LookupValues_Update'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zsystem.LookupValues_Update TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zmetric') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zmetric'
GO


IF NOT EXISTS(SELECT * FROM zsystem.schemas WHERE schemaID = 2000000032)
  INSERT INTO zsystem.schemas (schemaID, schemaName, [description], webPage)
       VALUES (2000000032, 'zmetric', 'CORE - Metrics', 'http://core/wiki/DB_zmetric')
GO


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'Recipients-IndexStats')
  INSERT INTO zsystem.settings ([group], [key], value, [description])
       VALUES ('zmetric', 'Recipients-IndexStats', '', 'Mail recipients for Index Stats notifications')
GO


---------------------------------------------------------------------------------------------------------------------------------


-- *** groupID from 30000 and up is reserved for CORE ***

IF OBJECT_ID('zmetric.groups') IS NULL
BEGIN
  CREATE TABLE zmetric.groups
  (
    groupID        smallint                                     NOT NULL,
    groupName      nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]  nvarchar(max)                                NULL,
    [order]        smallint                                     NOT NULL  DEFAULT 0,
    parentGroupID  smallint                                     NULL,
    --
    CONSTRAINT groups_PK PRIMARY KEY CLUSTERED (groupID)
  )
END
GRANT SELECT ON zmetric.groups TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- *** counterID from 30000 and up is reserved for CORE ***

IF OBJECT_ID('zmetric.counters') IS NULL
BEGIN
  CREATE TABLE zmetric.counters
  (
    counterID             smallint                                     NOT NULL,
    counterName           nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    groupID               smallint                                     NULL,
    [description]         nvarchar(max)                                NULL,
    subjectLookupTableID  int                                          NULL, -- Lookup table for subjectID, pointing to zsystem.lookupTables/Values
    keyLookupTableID      int                                          NULL, -- Lookup table for keyID, pointing to zsystem.lookupTables/Values
    [source]              nvarchar(200)                                NULL, -- Description of data source, f.e. table name
    subjectID             nvarchar(200)                                NULL, -- Description of subjectID column
    keyID                 nvarchar(200)                                NULL, -- Description of keyID column
    absoluteValue         bit                                          NOT NULL  DEFAULT 0, -- If set counter stores absolute value
    shortName             nvarchar(50)                                 NULL,
    [order]               smallint                                     NOT NULL  DEFAULT 0,
    procedureName         nvarchar(500)                                NULL, -- Procedure called to get data for the counter
    procedureOrder        tinyint                                      NOT NULL  DEFAULT 200,
    parentCounterID       smallint                                     NULL,
    createDate            datetime2(0)                                 NOT NULL  DEFAULT GETUTCDATE(),
    baseCounterID         smallint                                     NULL,

    -- *** deprecated column ***
    counterType           char(1)                                      NOT NULL  DEFAULT 'D', -- C:Column, D:Date, S:Simple, T:Time

    obsolete              bit                                          NOT NULL  DEFAULT 0,
    counterIdentifier     varchar(500)   COLLATE Latin1_General_CI_AI  NOT NULL, -- Identifier to use in code to make it readable and usable in other Metrics webs
    hidden                bit                                          NOT NULL  DEFAULT 0,
    published             bit                                          NOT NULL  DEFAULT 1,
    sourceType            varchar(20)                                  NULL, -- Used f.e. on EVE Metrics to say if counter comes from DB or DOOBJOB
    units                 varchar(20)                                  NULL, -- zmetric.columns.units overrides value set here
    counterTable          nvarchar(256)                                NULL, -- Stating in what table the counter data is stored
    userName              varchar(200)                                 NULL,
    config                varchar(max)                                 NULL,
    modifyDate            datetime2(0)                                 NOT NULL  DEFAULT GETUTCDATE(),
    --
    CONSTRAINT counters_PK PRIMARY KEY CLUSTERED (counterID)
  )

  CREATE NONCLUSTERED INDEX counters_IX_ParentCounter ON zmetric.counters (parentCounterID)

  CREATE UNIQUE NONCLUSTERED INDEX counters_UQ_Identifier ON zmetric.counters (counterIdentifier)
END
GRANT SELECT ON zmetric.counters TO zzp_server
GO


-- Data
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30007)
  INSERT INTO zmetric.counters (counterID, counterType, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30007, 'C', 'core.db.indexStats', 'DB Metrics - Index statistics', 'Index statistics saved daily by job. Note that user columns contain accumulated counts.', 2000000005)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30008)
  INSERT INTO zmetric.counters (counterID, counterType, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30008, 'C', 'core.db.tableStats', 'DB Metrics - Table statistics', 'Table statistics saved daily by job. Note that user columns contain accumulated counts.', 2000000006)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30009)
  INSERT INTO zmetric.counters (counterID, counterType, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30009, 'C', 'core.db.fileStats', 'DB Metrics - File statistics', 'File statistics saved daily by job. Note that most columns contain accumulated counts.', 2000000007)
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.columns') IS NULL
BEGIN
  CREATE TABLE zmetric.columns
  (
    counterID          smallint                                     NOT NULL,
    columnID           tinyint                                      NOT NULL,
    columnName         nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]      nvarchar(max)                                NULL,
    [order]            smallint                                     NOT NULL  DEFAULT 0,
    units              varchar(20)                                  NULL, -- If set here it overrides value in zmetric.counters.units
    counterTable       nvarchar(256)                                NULL, -- If set here it overrides value in zmetric.counters.counterTable
    --
    CONSTRAINT columns_PK PRIMARY KEY CLUSTERED (counterID, columnID)
  )
END
GRANT SELECT ON zmetric.columns TO zzp_server
GO


-- Data
-- DB Metrics - Index statistics
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 1)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30007, 1, 'rows')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 2)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30007, 2, 'total_kb')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 3)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30007, 3, 'used_kb')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 4)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30007, 4, 'data_kb')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 5)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30007, 5, 'user_seeks', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 6)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30007, 6, 'user_scans', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 7)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30007, 7, 'user_lookups', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007 AND columnID = 8)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30007, 8, 'user_updates', 'Accumulated count')
-- DB Metrics - Table statistics
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 1)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30008, 1, 'rows')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 2)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30008, 2, 'total_kb')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 3)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30008, 3, 'used_kb')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 4)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30008, 4, 'data_kb')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 5)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30008, 5, 'user_seeks', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 6)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30008, 6, 'user_scans', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 7)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30008, 7, 'user_lookups', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008 AND columnID = 8)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30008, 8, 'user_updates', 'Accumulated count')
-- DB Metrics - File statistics
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 1)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30009, 1, 'reads', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 2)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30009, 2, 'reads_kb', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 3)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30009, 3, 'io_stall_read', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 4)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30009, 4, 'writes', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 5)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30009, 5, 'writes_kb', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 6)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description]) VALUES (30009, 6, 'io_stall_write', 'Accumulated count')
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009 AND columnID = 7)
  INSERT INTO zmetric.columns (counterID, columnID, columnName) VALUES (30009, 7, 'size_kb')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.simpleCounters') IS NULL
BEGIN
  CREATE TABLE zmetric.simpleCounters
  (
    counterID    smallint      NOT NULL,  -- The counter, poining to zmetric.counters
    counterDate  datetime2(0)  NOT NULL,  -- The datetime
    value        float         NOT NULL,  -- The value of the counter
    --
    CONSTRAINT simpleCounters_PK PRIMARY KEY CLUSTERED (counterID, counterDate)
  )
END
GRANT SELECT ON zmetric.simpleCounters TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_ID') IS NOT NULL
  DROP FUNCTION zmetric.Counters_ID
GO
CREATE FUNCTION zmetric.Counters_ID(@counterIdentifier varchar(500))
RETURNS smallint
BEGIN
  DECLARE @counterID int
  SELECT @counterID = counterID FROM zmetric.counters WHERE counterIdentifier = @counterIdentifier
  RETURN @counterID
END
GO
GRANT EXEC ON zmetric.Counters_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.SimpleCounters_Insert') IS NOT NULL
  DROP PROCEDURE zmetric.SimpleCounters_Insert
GO
CREATE PROCEDURE zmetric.SimpleCounters_Insert
  @counterID    smallint,
  @value        float,
  @interval     varchar(3) = 'M', -- M:Minute, M2:2Minutes, M3:3Minutes. M5:5Minutes, M10:10Minutes, M15:15Minutes, M30:30Minutes, H:Hour
  @counterDate  datetime2(0) = NULL
AS
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval IS NOT NULL
  BEGIN
    SET @counterDate = CASE @interval WHEN 'H' THEN zutil.DateHour(@counterDate)
                                      WHEN 'M' THEN zutil.DateMinute(@counterDate)
                                      WHEN 'M2' THEN zutil.DateMinutes(@counterDate, 2)
                                      WHEN 'M3' THEN zutil.DateMinutes(@counterDate, 3)
                                      WHEN 'M5' THEN zutil.DateMinutes(@counterDate, 5)
                                      WHEN 'M10' THEN zutil.DateMinutes(@counterDate, 10)
                                      WHEN 'M15' THEN zutil.DateMinutes(@counterDate, 15)
                                      WHEN 'M30' THEN zutil.DateMinutes(@counterDate, 30)
                                      ELSE @counterDate END
  END

  INSERT INTO zmetric.simpleCounters (counterID, counterDate, value) VALUES (@counterID, @counterDate, @value)
GO
GRANT EXEC ON zmetric.SimpleCounters_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.SimpleCounters_Update') IS NOT NULL
  DROP PROCEDURE zmetric.SimpleCounters_Update
GO
CREATE PROCEDURE zmetric.SimpleCounters_Update
  @counterID    smallint,
  @value        float,
  @interval     varchar(3) = 'M', -- M:Minute, M2:2Minutes, M3:3Minutes. M5:5Minutes, M10:10Minutes, M15:15Minutes, M30:30Minutes, H:Hour
  @counterDate  datetime2(0) = NULL
AS
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval IS NOT NULL
  BEGIN
    SET @counterDate = CASE @interval WHEN 'H' THEN zutil.DateHour(@counterDate)
                                      WHEN 'M' THEN zutil.DateMinute(@counterDate)
                                      WHEN 'M2' THEN zutil.DateMinutes(@counterDate, 2)
                                      WHEN 'M3' THEN zutil.DateMinutes(@counterDate, 3)
                                      WHEN 'M5' THEN zutil.DateMinutes(@counterDate, 5)
                                      WHEN 'M10' THEN zutil.DateMinutes(@counterDate, 10)
                                      WHEN 'M15' THEN zutil.DateMinutes(@counterDate, 15)
                                      WHEN 'M30' THEN zutil.DateMinutes(@counterDate, 30)
                                      ELSE @counterDate END
  END

  UPDATE zmetric.simpleCounters SET value = value + @value WHERE counterID = @counterID AND counterDate = @counterDate
  IF @@ROWCOUNT = 0
  BEGIN TRY
    INSERT INTO zmetric.simpleCounters (counterID, counterDate, value) VALUES (@counterID, @counterDate, @value)
  END TRY
  BEGIN CATCH
    IF ERROR_NUMBER() = 2627 -- Violation of PRIMARY KEY constraint
      UPDATE zmetric.simpleCounters SET value = value + @value WHERE counterID = @counterID AND counterDate = @counterDate
    ELSE
    BEGIN
      EXEC zsystem.CatchError 'zmetric.SimpleCounters_Update'
      RETURN -1
    END
  END CATCH
GO
GRANT EXEC ON zmetric.SimpleCounters_Update TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.SimpleCounters_Select') IS NOT NULL
  DROP PROCEDURE zmetric.SimpleCounters_Select
GO
CREATE PROCEDURE zmetric.SimpleCounters_Select
  @counterID  smallint,
  @fromDate   datetime2(0) = NULL,
  @toDate     datetime2(0) = NULL,
  @rows       int = 1000000
AS
  SET NOCOUNT ON

  SELECT TOP (@rows) counterDate, value
    FROM zmetric.simpleCounters
   WHERE counterID = @counterID AND
         counterDate BETWEEN ISNULL(@fromDate, CONVERT(datetime2(0), '0001-01-01')) AND ISNULL(@toDate, CONVERT(datetime2(0), '9999-12-31'))
   ORDER BY counterDate
GO
GRANT EXEC ON zmetric.SimpleCounters_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0003, 'jorundur'
GO






-- ################################################################################################
-- # CORE.J.4                                                                                     #
-- ################################################################################################

EXEC zsystem.Versions_Start 'CORE.J', 0004, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Versions_Check') IS NOT NULL
  DROP PROCEDURE zsystem.Versions_Check
GO
CREATE PROCEDURE zsystem.Versions_Check
  @developer  varchar(20) = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @developers TABLE (developer varchar(20))

  IF @developer IS NULL
  BEGIN
    INSERT INTO @developers (developer)
         SELECT DISTINCT developer FROM zsystem.versions
  END
  ELSE
    INSERT INTO @developers (developer) VALUES (@developer)

  DECLARE @version int, @firstVersion int

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT developer FROM @developers ORDER BY developer
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @developer
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SELECT @firstVersion = MIN([version]) - 1 FROM zsystem.versions WHERE developer = @developer;

    WITH CTE (rowID, versionID, [version]) AS
    (
      SELECT ROW_NUMBER() OVER(ORDER BY [version]),
             [version] - @firstVersion, [version]
        FROM zsystem.versions
        WHERE developer = @developer
    )
    SELECT @version = MAX([version]) FROM CTE WHERE rowID = versionID

    SELECT developer,
           info = CASE WHEN [version] = @version THEN 'LAST CONTINUOUS VERSION' ELSE 'MISSING PRIOR VERSIONS' END,
           [version], versionDate, userName, executionCount, lastDate, coreVersion,
           firstDuration = zutil.TimeString(firstDuration), lastDuration = zutil.TimeString(lastDuration)
      FROM zsystem.versions
     WHERE developer = @developer AND [version] >= @version


    FETCH NEXT FROM @cursor INTO @developer
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO
GRANT EXEC ON zsystem.Versions_Check TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Paul Randal (http://www.sqlskills.com/blogs/paul/wait-statistics-or-please-tell-me-where-it-hurts)

IF OBJECT_ID('zdm.waitstats') IS NOT NULL
  DROP PROCEDURE zdm.waitstats
GO
CREATE PROCEDURE zdm.waitstats
  @percentageThreshold tinyint = 95
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  ;WITH waits AS
  (
    SELECT wait_type,
           wait_time_ms,
           resource_wait_time_ms = wait_time_ms - signal_wait_time_ms,
           signal_wait_time_ms,
           waiting_tasks_count,
           percentage = 100.0 * wait_time_ms / SUM (wait_time_ms) OVER(),
           rowNum = ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC)
      FROM sys.dm_os_wait_stats
     WHERE wait_type NOT IN (N'CLR_SEMAPHORE',      N'LAZYWRITER_SLEEP',            N'RESOURCE_QUEUE',   N'SQLTRACE_BUFFER_FLUSH',
                               N'SLEEP_TASK',       N'SLEEP_SYSTEMTASK',            N'WAITFOR',          N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
                               N'CHECKPOINT_QUEUE', N'REQUEST_FOR_DEADLOCK_SEARCH', N'XE_TIMER_EVENT',   N'XE_DISPATCHER_JOIN',
                               N'LOGMGR_QUEUE',     N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'BROKER_TASK_STOP', N'CLR_MANUAL_EVENT',
                               N'CLR_AUTO_EVENT',   N'DISPATCHER_QUEUE_SEMAPHORE',  N'TRACEWRITE',       N'XE_DISPATCHER_WAIT',
                               N'BROKER_TO_FLUSH',  N'BROKER_EVENTHANDLER',         N'FT_IFTSHC_MUTEX',  N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
                               N'DIRTY_PAGE_POLL',  N'SP_SERVER_DIAGNOSTICS_SLEEP')
  )
  SELECT W1.wait_type,
         W1.wait_time_ms,
         W1.resource_wait_time_ms,
         W1.signal_wait_time_ms,
         W1.waiting_tasks_count,
         percentage = CAST(W1.percentage AS DECIMAL (14, 2)),
         avg_wait_time_ms = CAST((W1.wait_time_ms / CONVERT(float, W1.waiting_tasks_count)) AS DECIMAL (14, 4)),
         avg_resource_wait_time_ms = CAST((W1.resource_wait_time_ms / CONVERT(float, W1.waiting_tasks_count)) AS DECIMAL (14, 4)),
         avg_signal_wait_time_ms = CAST((W1.signal_wait_time_ms / CONVERT(float, W1.waiting_tasks_count)) AS DECIMAL (14, 4))
    FROM waits AS W1
      INNER JOIN waits AS W2 ON W2.rowNum <= W1.rowNum
   GROUP BY W1.rowNum, W1.wait_type, W1.wait_time_ms, W1.resource_wait_time_ms, W1.signal_wait_time_ms, W1.waiting_tasks_count, W1.percentage
     HAVING SUM(W2.percentage) - W1.percentage < @percentageThreshold
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.panic') IS NOT NULL
  DROP PROCEDURE zdm.panic
GO
CREATE PROCEDURE zdm.panic
AS
  SET NOCOUNT ON

  PRINT ''
  PRINT '#######################'
  PRINT '# DBA Panic Checklist #'
  PRINT '#######################'
  PRINT ''
  PRINT 'Web page: http://wiki/display/db/DBA+Panic+Checklist'
  PRINT ''
  PRINT '------------------------------------------------'
  PRINT 'STORED PROCEDURES TO USE IN A PANIC SITUATION...'
  PRINT '------------------------------------------------'
  PRINT '  zdm.topsql        /  zdm.topsqlp'
  PRINT '  zdm.counters'
  PRINT '  zdm.sessioninfo   /  zdm.processinfo'
  PRINT '  zdm.transactions'
  PRINT '  zdm.applocks'
  PRINT '  zdm.memory'
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.BigintListToOrderedTable') IS NOT NULL
  DROP FUNCTION zutil.BigintListToOrderedTable
GO
CREATE FUNCTION zutil.BigintListToOrderedTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                number = CONVERT(bigint, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.BigintListToOrderedTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.BigintListToTable') IS NOT NULL
  DROP FUNCTION zutil.BigintListToTable
GO
CREATE FUNCTION zutil.BigintListToTable(@list varchar(max))
  RETURNS TABLE
  RETURN SELECT number = CONVERT(bigint, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.BigintListToTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.CharListToOrderedTable') IS NOT NULL
  DROP FUNCTION zutil.CharListToOrderedTable
GO
CREATE FUNCTION zutil.CharListToOrderedTable(@list nvarchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                string = SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n)
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.CharListToOrderedTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.CharListToOrderedTableTrim') IS NOT NULL
  DROP FUNCTION zutil.CharListToOrderedTableTrim
GO
CREATE FUNCTION zutil.CharListToOrderedTableTrim(@list nvarchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                string = LTRIM(RTRIM(SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n)))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.CharListToOrderedTableTrim TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.CharListToTable') IS NOT NULL
  DROP FUNCTION zutil.CharListToTable
GO
CREATE FUNCTION zutil.CharListToTable(@list nvarchar(max))
  RETURNS TABLE
  RETURN SELECT string = SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n)
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.CharListToTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.CharListToTableTrim') IS NOT NULL
  DROP FUNCTION zutil.CharListToTableTrim
GO
CREATE FUNCTION zutil.CharListToTableTrim(@list nvarchar(max))
  RETURNS TABLE
  RETURN SELECT string = LTRIM(RTRIM(SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n)))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.CharListToTableTrim TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.DateListToOrderedTable') IS NOT NULL
  DROP FUNCTION zutil.DateListToOrderedTable
GO
CREATE FUNCTION zutil.DateListToOrderedTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                dateValue = CONVERT(datetime2(0), SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.DateListToOrderedTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.DateListToTable') IS NOT NULL
  DROP FUNCTION zutil.DateListToTable
GO
CREATE FUNCTION zutil.DateListToTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT dateValue = CONVERT(datetime2(0), SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.DateListToTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.FloatListToOrderedTable') IS NOT NULL
  DROP FUNCTION zutil.FloatListToOrderedTable
GO
CREATE FUNCTION zutil.FloatListToOrderedTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                number = CONVERT(float, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.FloatListToOrderedTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.FloatListToTable') IS NOT NULL
  DROP FUNCTION zutil.FloatListToTable
GO
CREATE FUNCTION zutil.FloatListToTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT number = CONVERT(float, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.FloatListToTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.IntListToOrderedTable') IS NOT NULL
  DROP FUNCTION zutil.IntListToOrderedTable
GO
CREATE FUNCTION zutil.IntListToOrderedTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                number = CONVERT(int, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.IntListToOrderedTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.IntListToTable') IS NOT NULL
  DROP FUNCTION zutil.IntListToTable
GO
CREATE FUNCTION zutil.IntListToTable(@list varchar(max))
  RETURNS TABLE
  RETURN SELECT number = CONVERT(int, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.IntListToTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Itzik Ben-Gan

IF OBJECT_ID('zutil.MoneyListToOrderedTable') IS NOT NULL
  DROP FUNCTION zutil.MoneyListToOrderedTable
GO
CREATE FUNCTION zutil.MoneyListToOrderedTable(@list varchar(MAX))
  RETURNS TABLE
  RETURN SELECT row = ROW_NUMBER() OVER(ORDER BY n),
                number = CONVERT(money, SUBSTRING(@list, n, CHARINDEX(',', @list + ',', n) - n))
           FROM zutil.Numbers(LEN(@list) + 1)
          WHERE SUBSTRING(',' + @list, n, 1) = ','
GO
GRANT SELECT ON zutil.MoneyListToOrderedTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.tablesEx') IS NOT NULL
  DROP VIEW zsystem.tablesEx
GO
CREATE VIEW zsystem.tablesEx
AS
  SELECT fullName = S.schemaName + '.' + T.tableName,
         T.schemaID, S.schemaName, T.tableID, T.tableName, T.[description],
         T.tableType, T.logIdentity, T.copyStatic,
         T.keyID, T.keyID2, T.keyID3, T.sequence, T.keyName, T.keyDate, T.keyDateUTC,
         T.textTableID, T.textKeyID, T.textTableID2, T.textKeyID2, T.textTableID3, T.textKeyID3,
         T.link, T.disableEdit, T.disableDelete, T.disabledDatasets, T.revisionOrder, T.obsolete, T.denormalized
    FROM zsystem.tables T
      LEFT JOIN zsystem.schemas S ON S.schemaID = T.schemaID
GO
GRANT SELECT ON zsystem.tablesEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Identities_Insert') IS NOT NULL
  DROP PROCEDURE zsystem.Identities_Insert
GO
CREATE PROCEDURE zsystem.Identities_Insert
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @identityDate date
  SET @identityDate = DATEADD(minute, 5, GETUTCDATE())

  DECLARE @maxi int, @maxb bigint, @stmt nvarchar(4000), @objectID int

  DECLARE @tableID int, @tableName nvarchar(256), @keyID nvarchar(128), @keyDate nvarchar(128), @logIdentity tinyint

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT T.tableID, QUOTENAME(S.schemaName) + '.' + QUOTENAME(T.tableName), QUOTENAME(T.keyID), T.keyDate, T.logIdentity
          FROM zsystem.tables T
            INNER JOIN zsystem.schemas S ON S.schemaID = T.schemaID
         WHERE T.logIdentity IN (1, 2) AND ISNULL(T.keyID, '') != ''
         ORDER BY tableID
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @tableID, @tableName, @keyID, @keyDate, @logIdentity
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @objectID = OBJECT_ID(@tableName)
    IF @objectID IS NOT NULL
    BEGIN
      IF @keyDate IS NOT NULL
      BEGIN
        IF EXISTS(SELECT * FROM sys.columns WHERE [object_id] = @objectID AND name = @keyDate)
          SET @keyDate = QUOTENAME(@keyDate)
        ELSE
          SET @keyDate = NULL
      END

      IF @logIdentity = 1
      BEGIN
        SET @maxi = NULL
        SET @stmt = 'SELECT TOP 1 @p_maxi = ' + @keyID + ' FROM ' + @tableName
        IF @keyDate IS NOT NULL
          SET @stmt = @stmt + ' WHERE ' + @keyDate + ' < @p_date'
        SET @stmt = @stmt + ' ORDER BY ' + @keyID + ' DESC'
        EXEC sp_executesql @stmt, N'@p_maxi int OUTPUT, @p_date datetime2(0)', @maxi OUTPUT, @identityDate
        IF @maxi IS NOT NULL
        BEGIN
          SET @maxi = @maxi + 1
          INSERT INTO zsystem.identities (tableID, identityDate, identityInt)
               VALUES (@tableID, @identityDate, @maxi)
        END
      END
      ELSE
      BEGIN
        SET @maxb = NULL
        SET @stmt = 'SELECT TOP 1 @p_maxb = ' + @keyID + ' FROM ' + @tableName
        IF @keyDate IS NOT NULL
          SET @stmt = @stmt + ' WHERE ' + @keyDate + ' < @p_date'
        SET @stmt = @stmt + ' ORDER BY ' + @keyID + ' DESC'
        EXEC sp_executesql @stmt, N'@p_maxb bigint OUTPUT, @p_date datetime2(0)', @maxb OUTPUT, @identityDate
        IF @maxb IS NOT NULL
        BEGIN
          SET @maxb = @maxb + 1
          INSERT INTO zsystem.identities (tableID, identityDate, identityBigInt)
               VALUES (@tableID, @identityDate, @maxb)
        END
      END
    END

    FETCH NEXT FROM @cursor INTO @tableID, @tableName, @keyID, @keyDate, @logIdentity
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.tables WHERE tableID = 2000100014)
  INSERT INTO zsystem.tables (schemaID, tableID, tableName, [description], logIdentity, keyID, keyDate)
       VALUES (2000000001, 2000100014, 'events', 'Core - System - Events', 1, 'eventID', 'eventDate')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.schemas WHERE schemaID = 2000000034)
  INSERT INTO zsystem.schemas (schemaID, schemaName, [description])
       VALUES (2000000034, 'Operations', 'Special schema record, not actually a schema but rather pointing to the Operations database, allowing ops to register procs.')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.lookupTablesEx') IS NOT NULL
  DROP VIEW zsystem.lookupTablesEx
GO
CREATE VIEW zsystem.lookupTablesEx
AS
  SELECT L.lookupTableID, L.lookupTableName, L.lookupTableIdentifier, L.[description], L.schemaID, S.schemaName, L.tableID, T.tableName,
         L.sourceForID, L.[source], L.lookupID, L.parentID, L.parentLookupTableID, parentLookupTableName = L2.lookupTableName,
         L.link, L.label, L.hidden, L.obsolete
    FROM zsystem.lookupTables L
      LEFT JOIN zsystem.schemas S ON S.schemaID = L.schemaID
      LEFT JOIN zsystem.tables T ON T.tableID = L.tableID
      LEFT JOIN zsystem.lookupTables L2 ON L2.lookupTableID = L.parentLookupTableID
GO
GRANT SELECT ON zsystem.lookupTablesEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupTables_Insert') IS NOT NULL
  DROP PROCEDURE zsystem.LookupTables_Insert
GO
CREATE PROCEDURE zsystem.LookupTables_Insert
  @lookupTableID          int = NULL,            -- NULL means MAX-UNDER-2000000000 + 1
  @lookupTableName        nvarchar(200),
  @description            nvarchar(max) = NULL,
  @schemaID               int = NULL,            -- Link lookup table to a schema, just info
  @tableID                int = NULL,            -- Link lookup table to a table, just info
  @source                 nvarchar(200) = NULL,  -- Description of data source, f.e. table name
  @lookupID               nvarchar(200) = NULL,  -- Description of lookupID column
  @parentID               nvarchar(200) = NULL,  -- Description of parentID column
  @parentLookupTableID    int = NULL,
  @link                   nvarchar(500) = NULL,  -- If a link to a web page is needed
  @lookupTableIdentifier  varchar(500) = NULL,
  @sourceForID            varchar(20) = NULL,    -- EXTERNAL/TEXT/MAX
  @label                  nvarchar(200) = NULL   -- If a label is needed instead of lookup text
AS
  SET NOCOUNT ON

  IF @lookupTableID IS NULL
    SELECT @lookupTableID = MAX(lookupTableID) + 1 FROM zsystem.lookupTables WHERE lookupTableID < 2000000000
  IF @lookupTableID IS NULL SET @lookupTableID = 1

  IF @lookupTableIdentifier IS NULL SET @lookupTableIdentifier = @lookupTableID

  INSERT INTO zsystem.lookupTables
              (lookupTableID, lookupTableName, [description], schemaID, tableID, [source], lookupID, parentID, parentLookupTableID,
               link, lookupTableIdentifier, sourceForID, label)
       VALUES (@lookupTableID, @lookupTableName, @description, @schemaID, @tableID, @source, @lookupID, @parentID, @parentLookupTableID,
               @link, @lookupTableIdentifier, @sourceForID, @label)

  SELECT lookupTableID = @lookupTableID
GO
GRANT EXEC ON zsystem.LookupTables_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- this table is intended for normal key counters
--
-- normal key counters are key counters where you need to get top x records ordered by value (f.e. leaderboards)

IF OBJECT_ID('zmetric.keyCounters') IS NULL
BEGIN
  CREATE TABLE zmetric.keyCounters
  (
    counterID    smallint  NOT NULL,  -- Counter, poining to zmetric.counters
    counterDate  date      NOT NULL,  -- Date
    columnID     tinyint   NOT NULL,  -- Column if used, pointing to zmetric.columns, 0 if not used
    keyID        int       NOT NULL,  -- Key if used, f.e. if counting by country, 0 if not used
    value        float     NOT NULL,  -- Value
    --
    CONSTRAINT keyCounters_PK PRIMARY KEY CLUSTERED (counterID, columnID, keyID, counterDate)
  )

  CREATE NONCLUSTERED INDEX keyCounters_IX_CounterDate ON zmetric.keyCounters (counterID, counterDate, columnID, value)
END
GRANT SELECT ON zmetric.keyCounters TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- this table is intended for time detail of data stored in zmetric.keyCounters
--
-- the only difference between this table and zmetric.keyCounters is that counterDate is datetime2(0) and there is only a primary key and no extra index

IF OBJECT_ID('zmetric.keyTimeCounters') IS NULL
BEGIN
  CREATE TABLE zmetric.keyTimeCounters
  (
    counterID    smallint      NOT NULL,  -- counter, poining to zmetric.counters
    counterDate  datetime2(0)  NOT NULL,
    columnID     tinyint       NOT NULL,  -- column if used, pointing to zmetric.columns, 0 if not used
    keyID        int           NOT NULL,  -- key if used, f.e. if counting by country, 0 if not used
    value        float         NOT NULL,
    --
    CONSTRAINT keyTimeCounters_PK PRIMARY KEY CLUSTERED (counterID, columnID, keyID, counterDate)
  )
END
GRANT SELECT ON zmetric.keyTimeCounters TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- this table is intended for subject/key counters
--
-- this is basically a two-key version of zmetric.keyCounters where it was decided to use subjectID/keyID instead of keyID/keyID2

IF OBJECT_ID('zmetric.subjectKeyCounters') IS NULL
BEGIN
  CREATE TABLE zmetric.subjectKeyCounters
  (
    counterID    smallint  NOT NULL,  -- counter, poining to zmetric.counters
    counterDate  date      NOT NULL,
    columnID     tinyint   NOT NULL,  -- column if used, pointing to zmetric.columns, 0 if not used
    subjectID    int       NOT NULL,  -- subject if used, f.e. if counting for user or character, 0 if not used
    keyID        int       NOT NULL,  -- key if used, f.e. if counting kills for character per solar system, 0 if not used
    value        float     NOT NULL,
    --
    CONSTRAINT subjectKeyCounters_PK PRIMARY KEY CLUSTERED (counterID, columnID, subjectID, keyID, counterDate)
  )

  CREATE NONCLUSTERED INDEX subjectKeyCounters_IX_CounterDate ON zmetric.subjectKeyCounters (counterID, counterDate, columnID, value)
END
GRANT SELECT ON zmetric.subjectKeyCounters TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.groupsEx') IS NOT NULL
  DROP VIEW zmetric.groupsEx
GO
CREATE VIEW zmetric.groupsEx
AS
  WITH CTE ([level], fullName, parentGroupID, groupID, groupName, [description], [order]) AS
  (
      SELECT [level] = 1, fullName = CONVERT(nvarchar(4000), groupName),
             parentGroupID, groupID, groupName, [description], [order]
        FROM zmetric.groups G
       WHERE parentGroupID IS NULL
      UNION ALL
      SELECT CTE.[level] + 1, CTE.fullName + N', ' + CONVERT(nvarchar(4000), X.groupName),
             X.parentGroupID, X.groupID, X.groupName,  X.[description], X.[order]
        FROM CTE
          INNER JOIN zmetric.groups X ON X.parentGroupID = CTE.groupID
  )
  SELECT [level], fullName, parentGroupID, groupID, groupName, [description], [order]
    FROM CTE
GO
GRANT SELECT ON zmetric.groupsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.countersEx') IS NOT NULL
  DROP VIEW zmetric.countersEx
GO
CREATE VIEW zmetric.countersEx
AS
  SELECT C.groupID, G.groupName, C.counterID, C.counterName, C.counterType, C.counterTable, C.counterIdentifier, C.[description],
         C.subjectLookupTableID, subjectLookupTableIdentifier = LS.lookupTableIdentifier, subjectLookupTableName = LS.lookupTableName,
         C.keyLookupTableID, keyLookupTableIdentifier = LK.lookupTableIdentifier, keyLookupTableName = LK.lookupTableName,
         C.sourceType, C.[source], C.subjectID, C.keyID, C.absoluteValue, C.shortName,
         groupOrder = G.[order], C.[order], C.procedureName, C.procedureOrder, C.parentCounterID, C.createDate, C.modifyDate, C.userName,
         C.baseCounterID, C.hidden, C.published, C.units, C.obsolete
    FROM zmetric.counters C
      LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
      LEFT JOIN zsystem.lookupTables LS ON LS.lookupTableID = C.subjectLookupTableID
      LEFT JOIN zsystem.lookupTables LK ON LK.lookupTableID = C.keyLookupTableID
GO
GRANT SELECT ON zmetric.countersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.columnsEx') IS NOT NULL
  DROP VIEW zmetric.columnsEx
GO
CREATE VIEW zmetric.columnsEx
AS
  SELECT C.groupID, G.groupName, O.counterID, C.counterName, O.columnID, O.columnName, O.[description], O.units, O.counterTable, O.[order]
    FROM zmetric.columns O
      LEFT JOIN zmetric.counters C ON C.counterID = O.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
GO
GRANT SELECT ON zmetric.columnsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.simpleCountersEx') IS NOT NULL
  DROP VIEW zmetric.simpleCountersEx
GO
CREATE VIEW zmetric.simpleCountersEx
AS
  SELECT C.groupID, G.groupName, SC.counterID, C.counterName, SC.counterDate, SC.value
    FROM zmetric.simpleCounters SC
      LEFT JOIN zmetric.counters C ON C.counterID = SC.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
GO
GRANT SELECT ON zmetric.simpleCountersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.keyCountersEx') IS NOT NULL
  DROP VIEW zmetric.keyCountersEx
GO
CREATE VIEW zmetric.keyCountersEx
AS
  SELECT C.groupID, G.groupName, K.counterID, C.counterName, K.counterDate, K.columnID, O.columnName,
         K.keyID, keyText = ISNULL(L.[fullText], L.lookupText), K.[value]
    FROM zmetric.keyCounters K
      LEFT JOIN zmetric.counters C ON C.counterID = K.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
        LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = C.keyLookupTableID AND L.lookupID = K.keyID
      LEFT JOIN zmetric.columns O ON O.counterID = K.counterID AND O.columnID = K.columnID
GO
GRANT SELECT ON zmetric.keyCountersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.keyTimeCountersEx') IS NOT NULL
  DROP VIEW zmetric.keyTimeCountersEx
GO
CREATE VIEW zmetric.keyTimeCountersEx
AS
  SELECT C.groupID, G.groupName, T.counterID, C.counterName, T.counterDate, T.columnID, O.columnName,
         T.keyID, keyText = ISNULL(L.[fullText], L.lookupText), T.[value]
    FROM zmetric.keyTimeCounters T
      LEFT JOIN zmetric.counters C ON C.counterID = T.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
        LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = C.keyLookupTableID AND L.lookupID = T.keyID
      LEFT JOIN zmetric.columns O ON O.counterID = T.counterID AND O.columnID = T.columnID
GO
GRANT SELECT ON zmetric.keyTimeCountersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.subjectKeyCountersEx') IS NOT NULL
  DROP VIEW zmetric.subjectKeyCountersEx
GO
CREATE VIEW zmetric.subjectKeyCountersEx
AS
  SELECT C.groupID, G.groupName, SK.counterID, C.counterName, SK.counterDate, SK.columnID, O.columnName,
         SK.subjectID, subjectText = ISNULL(LS.[fullText], LS.lookupText), SK.keyID, keyText = ISNULL(LK.[fullText], LK.lookupText), SK.[value]
    FROM zmetric.subjectKeyCounters SK
      LEFT JOIN zmetric.counters C ON C.counterID = SK.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
        LEFT JOIN zsystem.lookupValues LS ON LS.lookupTableID = C.subjectLookupTableID AND LS.lookupID = SK.subjectID
        LEFT JOIN zsystem.lookupValues LK ON LK.lookupTableID = C.keyLookupTableID AND LK.lookupID = SK.keyID
      LEFT JOIN zmetric.columns O ON O.counterID = SK.counterID AND O.columnID = SK.columnID
GO
GRANT SELECT ON zmetric.subjectKeyCountersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_Insert') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_Insert
GO
CREATE PROCEDURE zmetric.KeyCounters_Insert
  @counterID    smallint,
  @columnID     tinyint = 0,
  @keyID        int = 0,
  @value        float,
  @interval     char(1) = 'D', -- D:Day, W:Week, M:Month, Y:Year
  @counterDate  date = NULL
AS
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value)
       VALUES (@counterID, @counterDate, @columnID, @keyID, @value)
GO
GRANT EXEC ON zmetric.KeyCounters_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_Update') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_Update
GO
CREATE PROCEDURE zmetric.KeyCounters_Update
  @counterID    smallint,
  @columnID     tinyint = 0,
  @keyID        int = 0,
  @value        float,
  @interval     char(1) = 'D', -- D:Day, W:Week, M:Month, Y:Year
  @counterDate  date = NULL
AS
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  UPDATE zmetric.keyCounters
      SET value = value + @value
    WHERE counterID = @counterID AND columnID = @columnID AND keyID = @keyID AND counterDate = @counterDate
  IF @@ROWCOUNT = 0
  BEGIN TRY
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value)
          VALUES (@counterID, @counterDate, @columnID, @keyID, @value)
  END TRY
  BEGIN CATCH
    IF ERROR_NUMBER() = 2627 -- Violation of PRIMARY KEY constraint
    BEGIN
      UPDATE zmetric.keyCounters
         SET value = value + @value
       WHERE counterID = @counterID AND columnID = @columnID AND keyID = @keyID AND counterDate = @counterDate
    END
    ELSE
    BEGIN
      EXEC zsystem.CatchError 'zmetric.KeyCounters_Update'
      RETURN -1
    END
  END CATCH
GO
GRANT EXEC ON zmetric.KeyCounters_Update TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_InsertMulti') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_InsertMulti
GO
CREATE PROCEDURE zmetric.KeyCounters_InsertMulti
  @counterID      smallint,
  @interval       char(1) = 'D',  -- D:Day, W:Week, M:Month, Y:Year
  @counterDate    date = NULL,
  @lookupTableID  int,
  @keyID          int = NULL,     -- If NULL then zsystem.Texts_ID is used
  @keyText        nvarchar(450),
  @value1         float = NULL,
  @value2         float = NULL,
  @value3         float = NULL,
  @value4         float = NULL,
  @value5         float = NULL,
  @value6         float = NULL,
  @value7         float = NULL,
  @value8         float = NULL,
  @value9         float = NULL,
  @value10        float = NULL
AS
  -- Set values for multiple columns
  -- @value1 goes into columnID = 1, @value2 goes into columnID = 2 and so on
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  IF @keyText IS NOT NULL
    EXEC @keyID = zsystem.LookupValues_Update @lookupTableID, @keyID, @keyText

  IF ISNULL(@value1, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, @keyID, @value1)

  IF ISNULL(@value2, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, @keyID, @value2)

  IF ISNULL(@value3, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, @keyID, @value3)

  IF ISNULL(@value4, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 4, @keyID, @value4)

  IF ISNULL(@value5, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 5, @keyID, @value5)

  IF ISNULL(@value6, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 6, @keyID, @value6)

  IF ISNULL(@value7, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 7, @keyID, @value7)

  IF ISNULL(@value8, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 8, @keyID, @value8)

  IF ISNULL(@value9, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 9, @keyID, @value9)

  IF ISNULL(@value10, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 10, @keyID, @value10)
GO
GRANT EXEC ON zmetric.KeyCounters_InsertMulti TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_UpdateMulti') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_UpdateMulti
GO
CREATE PROCEDURE zmetric.KeyCounters_UpdateMulti
  @counterID      smallint,
  @interval       char(1) = 'D',  -- D:Day, W:Week, M:Month, Y:Year
  @counterDate    date = NULL,
  @lookupTableID  int,
  @keyID          int = NULL,     -- If NULL then zsystem.Texts_ID is used
  @keyText        nvarchar(450),
  @value1         float = NULL,
  @value2         float = NULL,
  @value3         float = NULL,
  @value4         float = NULL,
  @value5         float = NULL,
  @value6         float = NULL,
  @value7         float = NULL,
  @value8         float = NULL,
  @value9         float = NULL,
  @value10        float = NULL
AS
  -- Set values for multiple columns
  -- @value1 goes into columnID = 1, @value2 goes into columnID = 2 and so on
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  IF @keyText IS NOT NULL
    EXEC @keyID = zsystem.LookupValues_Update @lookupTableID, @keyID, @keyText

  IF ISNULL(@value1, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value1 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 1 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, @keyID, @value1)
  END

  IF ISNULL(@value2, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value2 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 2 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, @keyID, @value2)
  END

  IF ISNULL(@value3, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value3 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 3 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, @keyID, @value3)
  END

  IF ISNULL(@value4, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value4 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 4 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 4, @keyID, @value4)
  END

  IF ISNULL(@value5, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value5 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 5 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 5, @keyID, @value5)
  END

  IF ISNULL(@value6, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value6 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 6 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 6, @keyID, @value6)
  END

  IF ISNULL(@value7, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value7 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 7 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 7, @keyID, @value7)
  END

  IF ISNULL(@value8, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value8 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 8 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 8, @keyID, @value8)
  END

  IF ISNULL(@value9, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value9 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 9 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 9, @keyID, @value9)
  END

  IF ISNULL(@value10, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value10 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 10 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 10, @keyID, @value10)
  END
GO
GRANT EXEC ON zmetric.KeyCounters_UpdateMulti TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


update zsystem.jobs set [sql] = 'EXEC zmetric.Counters_SaveStats' WHERE jobID = 2000000011 and [sql] like '%zmetric.ColumnCounters_SaveStats%'
delete from zsystem.jobs where jobID = 2000000012 AND [sql] like '%zmetric.IndexStats_Mail%'
go


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveIndexStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveIndexStats', '0', '0', 'Save index stats daily to zmetric.keyCounters (set to "1" to activate)')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveFileStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveFileStats', '0', '0', 'Save file stats daily to zmetric.keyCounters (set to "1" to activate).  Note that file stats are saved for server so only one database needs to save file stats.')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveWaitStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveWaitStats', '0', '0', 'Save wait stats daily to zmetric.keyCounters (set to "1" to activate)  Note that waits stats are saved for server so only one database needs to save wait stats.')
GO


---------------------------------------------------------------------------------------------------------------------------------


-- core.db.waitTypes
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000008)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000008, 'core.db.waitTypes', 'DB - Wait types')
GO

-- core.db.waitStats
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30025)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30025, 'zmetric.keyCounters', 'core.db.waitStats', 'DB - Wait statistics', 'Wait statistics saved daily by job. Note that most columns contain accumulated counts.', 2000000008)
GO
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30025)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30025, 1, 'waiting_tasks_count', 'Accumulated count'), (30025, 2, 'wait_time_ms', 'Accumulated count'), (30025, 3, 'signal_wait_time_ms', 'Accumulated count')
GO


---------------------------------------------------------------------------------------------------------------------------------



update zmetric.counters set counterTable = 'zmetric.keyCounters' where counterID = 30007 and counterIdentifier = 'core.db.indexStats' AND counterTable IS NULL
update zmetric.counters set counterTable = 'zmetric.keyCounters' where counterID = 30008 and counterIdentifier = 'core.db.tableStats' AND counterTable IS NULL
update zmetric.counters set counterTable = 'zmetric.keyCounters' where counterID = 30009 and counterIdentifier = 'core.db.fileStats' AND counterTable IS NULL
go


update zsystem.lookupTables set lookupTableName = 'DB - Procs' where lookupTableID = 2000000001 and lookupTableName = 'DB Metrics - Procs'

update zsystem.lookupTables set lookupTableName = 'DB - Indexes' where lookupTableID = 2000000005 and lookupTableName = 'DB Metrics - Indexes'
update zsystem.lookupTables set lookupTableName = 'DB - Tables' where lookupTableID = 2000000006 and lookupTableName = 'DB Metrics - Tables'
update zsystem.lookupTables set lookupTableName = 'DB - Filegroups' where lookupTableID = 2000000007 and lookupTableName = 'DB Metrics - Filegroups'
go

update zmetric.counters set counterName = 'DB - Index statistics' where counterID = 30007 and counterName = 'DB Metrics - Index statistics'
update zmetric.counters set counterName = 'DB - Table statistics' where counterID = 30008 and counterName = 'DB Metrics - Table statistics'
update zmetric.counters set counterName = 'DB - File statistics' where counterID = 30009 and counterName = 'DB Metrics - File statistics'
go



---------------------------------------------------------------------------------------------------------------------------------

update zsystem.jobs set orderID = -7 where jobID = 2000000031 and jobName = 'CORE - zsystem - interval overflow alert' and orderID = -10
go


---------------------------------------------------------------------------------------------------------------------------------

-- core.db.procStats
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30026)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30026, 'zmetric.keyCounters', 'core.db.procStats', 'DB - Proc statistics', 'Proc statistics saved daily by job. Note that most columns contain accumulated counts.', 2000000001)
GO
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30026)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30026, 1, 'execution_count', 'Accumulated count'), (30026, 2, 'total_logical_reads', 'Accumulated count'), (30026, 3, 'total_logical_writes', 'Accumulated count'),
              (30026, 4, 'total_worker_time', 'Accumulated count'), (30026, 5, 'total_elapsed_time', 'Accumulated count')
GO

IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveProcStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveProcStats', '0', '0', 'Save proc stats daily to zmetric.keyCounters (set to "1" to activate).')
GO


---------------------------------------------------------------------------------------------------------------------------------


update zsystem.settings set [description] = 'Save index stats daily to zmetric.keyCounters (set to "1" to activate).' where [group] = 'zmetric' AND [key] = 'SaveIndexStats'
update zsystem.settings set [description] = 'Save wait stats daily to zmetric.keyCounters (set to "1" to activate).  Note that waits stats are saved for server so only one database needs to save wait stats.' where [group] = 'zmetric' AND [key] = 'SaveWaitStats'
go


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000009)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000009, 'core.db.perfCounters', 'DB - Performance counters')
GO


IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30027)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30027, 'zmetric.keyCounters', 'core.db.perfCountersTotal', 'DB - Performance counters - Total', 'Total performance counters saved daily by job (see proc zmetric.KeyCounters_SavePerfCounters). Note that value saved is accumulated count.', 2000000009)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30028)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID)
       VALUES (30028, 'zmetric.keyCounters', 'core.db.perfCountersInstance', 'DB - Performance counters - Instance', 'Instance performance counters saved daily by job (see proc zmetric.KeyCounters_SavePerfCounters). Note that value saved is accumulated count.', 2000000009)
GO


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SavePerfCountersTotal')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SavePerfCountersTotal', '0', '0', 'Save total performance counters daily to zmetric.keyCounters (set to "1" to activate).')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SavePerfCountersInstance')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SavePerfCountersInstance', '0', '0', 'Save instance performance counters daily to zmetric.keyCounters (set to "1" to activate).')
GO


---------------------------------------------------------------------------------------------------------------------------------


update zmetric.counters
   set [description] = 'Index statistics saved daily by job (see proc zmetric.KeyCounters_SaveIndexStats). Note that user columns contain accumulated counts.'
 where counterID = 30007
update zmetric.counters
   set [description] = 'Table statistics saved daily by job (see proc zmetric.KeyCounters_SaveIndexStats). Note that user columns contain accumulated counts.'
 where counterID = 30008
update zmetric.counters
   set [description] = 'File statistics saved daily by job (see proc zmetric.KeyCounters_SaveFileStats). Note that all columns except size_kb contain accumulated counts.'
 where counterID = 30009
update zmetric.counters
   set [description] = 'Wait statistics saved daily by job (see proc zmetric.KeyCounters_SaveWaitStats). Note that all columns contain accumulated counts.'
 where counterID = 30025
update zmetric.counters
   set [description] = 'Proc statistics saved daily by job (see proc zmetric.KeyCounters_SaveProcStats). Note that all columns contain accumulated counts.'
 where counterID = 30026
go


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveProcStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveProcStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveProcStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveProcStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30026 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30026 AND counterDate = @counterDate)
        RAISERROR ('Proc stats data exists', 16, 1)
    END

    -- PROC STATISTICS
    DECLARE @object_name nvarchar(300), @execution_count bigint, @total_logical_reads bigint, @total_logical_writes bigint, @total_worker_time bigint, @total_elapsed_time bigint

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT S.name + '.' + O.name, SUM(P.execution_count), SUM(P.total_logical_reads), SUM(P.total_logical_writes), SUM(P.total_worker_time), SUM(P.total_elapsed_time)
            FROM sys.dm_exec_procedure_stats P
              INNER JOIN sys.objects O ON O.[object_id] = P.[object_id]
                INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
           WHERE P.database_id = DB_ID()
           GROUP BY S.name + '.' + O.name
           ORDER BY 1
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @object_name, @execution_count, @total_logical_reads, @total_logical_writes, @total_worker_time, @total_elapsed_time
    WHILE @@FETCH_STATUS = 0
    BEGIN
      -- removing digits at the end of string (max two digits)
      IF CHARINDEX(RIGHT(@object_name, 1), '0123456789') > 0
        SET @object_name = LEFT(@object_name, LEN(@object_name) - 1)
      IF CHARINDEX(RIGHT(@object_name, 1), '0123456789') > 0
        SET @object_name = LEFT(@object_name, LEN(@object_name) - 1)

      EXEC zmetric.KeyCounters_UpdateMulti 30026, 'D', @counterDate, 2000000001, NULL, @object_name, @execution_count, @total_logical_reads, @total_logical_writes, @total_worker_time, @total_elapsed_time

      FETCH NEXT FROM @cursor INTO @object_name, @execution_count, @total_logical_reads, @total_logical_writes, @total_worker_time, @total_elapsed_time
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveProcStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveFileStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveFileStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveFileStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveFileStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30009 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30009 AND counterDate = @counterDate)
        RAISERROR ('File stats data exists', 16, 1)
    END

    -- FILE STATISTICS
    DECLARE @database_name nvarchar(200), @file_type nvarchar(20), @filegroup_name nvarchar(200),
            @reads bigint, @reads_kb bigint, @io_stall_read bigint, @writes bigint, @writes_kb bigint, @io_stall_write bigint, @size_kb bigint,
            @keyText nvarchar(450)

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT database_name = D.name,
                 file_type = CASE WHEN M.type_desc = 'ROWS' THEN 'DATA' ELSE M.type_desc END,
                 [filegroup_name] = F.name,
                 SUM(S.num_of_reads), SUM(S.num_of_bytes_read) / 1024, SUM(S.io_stall_read_ms),
                 SUM(S.num_of_writes), SUM(S.num_of_bytes_written) / 1024, SUM(S.io_stall_write_ms),
                 SUM(S.size_on_disk_bytes) / 1024
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) S
              LEFT JOIN sys.databases D ON D.database_id = S.database_id
              LEFT JOIN sys.master_files M ON M.database_id = S.database_id AND M.[file_id] = S.[file_id]
                LEFT JOIN sys.filegroups F ON S.database_id = DB_ID() AND F.data_space_id = M.data_space_id
           GROUP BY D.name, M.type_desc, F.name
           ORDER BY database_name, M.type_desc DESC
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @database_name, @file_type, @filegroup_name, @reads, @reads_kb, @io_stall_read, @writes, @writes_kb, @io_stall_write, @size_kb
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @keyText = @database_name + ' :: ' + ISNULL(@filegroup_name, @file_type)

      EXEC zmetric.KeyCounters_InsertMulti 30009, 'D', @counterDate, 2000000007, NULL, @keyText,  @reads, @reads_kb, @io_stall_read, @writes, @writes_kb, @io_stall_write, @size_kb

      FETCH NEXT FROM @cursor INTO @database_name, @file_type, @filegroup_name, @reads, @reads_kb, @io_stall_read, @writes, @writes_kb, @io_stall_write, @size_kb
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveFileStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveWaitStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveWaitStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveWaitStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveWaitStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30025 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30025 AND counterDate = @counterDate)
        RAISERROR ('Wait stats data exists', 16, 1)
    END

    -- WAIT STATISTICS
    DECLARE @wait_type nvarchar(100), @waiting_tasks_count bigint, @wait_time_ms bigint, @signal_wait_time_ms bigint

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms FROM sys.dm_os_wait_stats WHERE waiting_tasks_count > 0
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @wait_type, @waiting_tasks_count, @wait_time_ms, @signal_wait_time_ms
    WHILE @@FETCH_STATUS = 0
    BEGIN
      EXEC zmetric.KeyCounters_InsertMulti 30025, 'D', @counterDate, 2000000008, NULL, @wait_type,  @waiting_tasks_count, @wait_time_ms, @signal_wait_time_ms

      FETCH NEXT FROM @cursor INTO @wait_type, @waiting_tasks_count, @wait_time_ms, @signal_wait_time_ms
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveWaitStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SavePerfCountersInstance') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SavePerfCountersInstance
GO
CREATE PROCEDURE zmetric.KeyCounters_SavePerfCountersInstance
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SavePerfCountersInstance') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30028 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30028 AND counterDate = @counterDate)
        RAISERROR ('Performance counters instance data exists', 16, 1)
    END

    -- PERFORMANCE COUNTERS INSTANCE
    DECLARE @object_name nvarchar(200), @counter_name nvarchar(200), @cntr_value bigint, @keyID int, @keyText nvarchar(450)

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT REPLACE(RTRIM([object_name]), 'SQLServer:', ''), RTRIM(counter_name), cntr_value
            FROM sys.dm_os_performance_counters
           WHERE cntr_type = 272696576 AND cntr_value != 0 AND instance_name = DB_NAME()
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @keyText = @object_name + ' :: ' + @counter_name

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, @keyText

      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30028, @counterDate, 0, @keyID, @cntr_value)

      FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SavePerfCountersInstance'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0004, 'jorundur'
GO






-- ################################################################################################
-- # CORE.J.5                                                                                     #
-- ################################################################################################

EXEC zsystem.Versions_Start 'CORE.J', 0005, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


-- Based on code from Ben Dill

IF OBJECT_ID('zsystem.PrintMax') IS NOT NULL
  DROP PROCEDURE zsystem.PrintMax
GO
CREATE PROCEDURE zsystem.PrintMax
  @str  nvarchar(max)
AS
  SET NOCOUNT ON

  IF @str IS NULL
    RETURN

  DECLARE @reversed nvarchar(max), @break int

  WHILE (LEN(@str) > 4000)
  BEGIN
    SET @reversed = REVERSE(LEFT(@str, 4000))

    SET @break = CHARINDEX(CHAR(10) + CHAR(13), @reversed)

    IF @break = 0
    BEGIN
      PRINT LEFT(@str, 4000)
      SET @str = RIGHT(@str, LEN(@str) - 4000)
    END
    ELSE
    BEGIN
      PRINT LEFT(@str, 4000 - @break + 1)
      SET @str = RIGHT(@str, LEN(@str) - 4000 + @break - 1)
    END
  END

  IF LEN(@str) > 0
    PRINT @str
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.SendLongRunningMail') IS NOT NULL
  DROP PROCEDURE zdm.SendLongRunningMail
GO
CREATE PROCEDURE zdm.SendLongRunningMail
  @minutes  smallint = 10,
  @rows     tinyint = 10
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @recipients varchar(max)
  SET @recipients = zsystem.Settings_Value('zdm', 'Recipients-LongRunning')
  IF @recipients = '' RETURN

  DECLARE @ignoreSQL nvarchar(max)
  SET @ignoreSQL = zsystem.Settings_Value('zdm', 'LongRunning-IgnoreSQL')

  DECLARE @session_id int, @start_time datetime2(0), @text nvarchar(max)

  DECLARE @stmt nvarchar(max), @cursor CURSOR
  SET @stmt = '
SET @p_cursor = CURSOR LOCAL FAST_FORWARD
  FOR SELECT TOP (@p_rows) R.session_id, R.start_time, S.[text]
        FROM sys.dm_exec_requests R
          CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) S
       WHERE R.session_id != @@SPID AND R.start_time < DATEADD(minute, -@p_minutes, GETDATE())'
  IF @ignoreSQL != ''
    SELECT @stmt = @stmt + ' AND S.[text] NOT LIKE ''' + string + '''' FROM zutil.CharListToTable(@ignoreSQL)
  SET @stmt = @stmt + '
         ORDER BY R.start_time
OPEN @p_cursor'

  EXEC sp_executesql @stmt, N'@p_cursor CURSOR OUTPUT, @p_rows tinyint, @p_minutes smallint', @cursor OUTPUT, @rows, @minutes
  FETCH NEXT FROM @cursor INTO @session_id, @start_time, @text
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @text = CHAR(13) + '   getdate: ' + CONVERT(nvarchar, GETDATE(), 120)
              + CHAR(13) + 'start_time: ' + CONVERT(nvarchar, @start_time, 120)
              + CHAR(13) + 'session_id: ' + CONVERT(nvarchar, @session_id)
              + CHAR(13) + CHAR(13) + @text
    EXEC zsystem.SendMail @recipients, 'LONG RUNNING SQL', @text

    FETCH NEXT FROM @cursor INTO @session_id, @start_time, @text
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.describe') IS NOT NULL
  DROP PROCEDURE zdm.describe
GO
CREATE PROCEDURE zdm.describe
  @objectName  nvarchar(256)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @schemaID int, @schemaName nvarchar(128), @objectID int,
          @type char(2), @typeDesc nvarchar(60),
          @createDate datetime2(0), @modifyDate datetime2(0), @isMsShipped bit,
          @i int, @text nvarchar(max), @parentID int

  SET @i = CHARINDEX('.', @objectName)
  IF @i > 0
  BEGIN
    SET @schemaName = SUBSTRING(@objectName, 1, @i - 1)
    SET @objectName = SUBSTRING(@objectName, @i + 1, 256)
    IF CHARINDEX('.', @objectName) > 0
    BEGIN
      RAISERROR ('Object name invalid', 16, 1)
      RETURN -1
    END

    SELECT @schemaID = [schema_id] FROM sys.schemas WHERE LOWER(name) = LOWER(@schemaName)
    IF @schemaID IS NULL
    BEGIN
      RAISERROR ('Schema not found', 16, 1)
      RETURN -1
    END
  END

  IF @schemaID IS NULL
  BEGIN
    SELECT TOP 2 @objectID = [object_id], @type = [type], @typeDesc = type_desc,
                 @createDate = create_date, @modifyDate = modify_date, @isMsShipped = is_ms_shipped
      FROM sys.objects
     WHERE LOWER(name) = LOWER(@objectName)
  END
  ELSE
  BEGIN
    SELECT TOP 2 @objectID = [object_id], @type = [type], @typeDesc = type_desc,
                 @createDate = create_date, @modifyDate = modify_date, @isMsShipped = is_ms_shipped
      FROM sys.objects
     WHERE [schema_id] = @schemaID AND LOWER(name) = LOWER(@objectName)
  END
  IF @@ROWCOUNT = 1
  BEGIN
    IF @schemaID IS NULL
      SELECT @schemaID = [schema_id] FROM sys.objects WHERE [object_id] = @objectID
    IF @schemaName IS NULL
      SELECT @schemaName = name FROM sys.schemas WHERE [schema_id] = @schemaID

    IF @type IN ('V', 'P', 'FN', 'IF') -- View, Procedure, Scalar Function, Table Function
    BEGIN
      PRINT ''
      SET @text = OBJECT_DEFINITION(OBJECT_ID(@schemaName + '.' + @objectName))
      EXEC zsystem.PrintMax @text
    END
    ELSE IF @type = 'C' -- Check Constraint
    BEGIN
      PRINT ''
      SELECT @text = [definition], @parentID = parent_object_id
        FROM sys.check_constraints
       WHERE [object_id] = @objectID
      EXEC zsystem.PrintMax @text
    END
    ELSE IF @type = 'D' -- Default Constraint
    BEGIN
      PRINT ''
      SELECT @text = C.name + ' = ' + DC.[definition], @parentID = DC.parent_object_id
        FROM sys.default_constraints DC
          INNER JOIN sys.columns C ON C.[object_id] = DC.parent_object_id AND C.column_id = DC.parent_column_id
       WHERE DC.[object_id] = @objectID
      EXEC zsystem.PrintMax @text
    END
    ELSE IF @type IN ('U', 'IT', 'S', 'PK') -- User Table, Internal Table, System Table, Primary Key
    BEGIN
      DECLARE @tableID int, @rows bigint
      IF @type = 'PK' -- Primary Key
      BEGIN
        SELECT [object_id], [object_name] = @schemaName + '.' + @objectName, [type], type_desc, create_date, modify_date, is_ms_shipped, parent_object_id
          FROM sys.objects
         WHERE [object_id] = @objectID

        SELECT @parentID = parent_object_id FROM sys.objects  WHERE [object_id] = @objectID
        SET @tableID = @parentID
      END
      ELSE
        SET @tableID = @objectID

      SELECT @rows = SUM(P.row_count)
        FROM sys.indexes I
          INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
       WHERE I.[object_id] = @tableID AND I.index_id IN (0, 1)

      SELECT [object_id], [object_name] = @schemaName + '.' + @objectName, [type], type_desc, [rows] = @rows, create_date, modify_date, is_ms_shipped
        FROM sys.objects
       WHERE [object_id] = @tableID

      SELECT C.column_id, column_name = C.name, [type_name] = TYPE_NAME(C.system_type_id), C.max_length, C.[precision], C.scale,
             C.collation_name, C.is_nullable, C.is_identity, [default] = D.[definition]
        FROM sys.columns C
          LEFT JOIN sys.default_constraints D ON D.parent_object_id = C.[object_id] AND D.parent_column_id = C.column_id
       WHERE C.[object_id] = @tableID
       ORDER BY C.column_id

      SELECT index_id, index_name = name, [type], type_desc, is_unique, is_primary_key, is_unique_constraint, has_filter, fill_factor, has_filter, filter_definition
        FROM sys.indexes
       WHERE [object_id] = @tableID
       ORDER BY index_id

      SELECT index_name = I.name, IC.key_ordinal, column_name = C.name, IC.is_included_column
        FROM sys.indexes I
          INNER JOIN sys.index_columns IC ON IC.[object_id] = I.[object_id] AND IC.index_id = I.index_id
            INNER JOIN sys.columns C ON C.[object_id] = IC.[object_id] AND C.column_id = IC.column_id
       WHERE I.[object_id] = @tableID
       ORDER BY I.index_id, IC.key_ordinal
    END
    ELSE
    BEGIN
      PRINT ''
      PRINT 'EXTRA INFORMATION NOT AVAILABLE FOR THIS TYPE OF OBJECT!'
    END

    IF @type NOT IN ('U', 'IT', 'S', 'PK')
    BEGIN
      PRINT REPLICATE('_', 100)
      IF @isMsShipped = 1
        PRINT 'THIS IS A MICROSOFT OBJECT'

      IF @parentID IS NOT NULL
        PRINT '  PARENT: ' + OBJECT_SCHEMA_NAME(@parentID) + '.' + OBJECT_NAME(@parentID)

      PRINT '    Name: ' + @schemaName + '.' + @objectName
      PRINT '    Type: ' + @typeDesc
      PRINT ' Created: ' + CONVERT(varchar, @createDate, 120)
      PRINT 'Modified: ' + CONVERT(varchar, @modifyDate, 120)
    END
  END
  ELSE
  BEGIN
    IF @schemaID IS NULL
    BEGIN
      SELECT O.[object_id], [object_name] = S.name + '.' + O.name, O.[type], O.type_desc, O.parent_object_id,
             O.create_date, O.modify_date, O.is_ms_shipped
        FROM sys.objects O
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
       WHERE LOWER(O.name) LIKE '%' + LOWER(@objectName) + '%'
       ORDER BY CASE O.[type] WHEN 'U' THEN '_A' WHEN 'V' THEN '_B' WHEN 'P' THEN '_C' WHEN 'FN' THEN '_D' WHEN 'IF' THEN '_E' WHEN 'PK' THEN '_F' ELSE O.[type] END,
                LOWER(S.name), LOWER(O.name)
    END
    ELSE
    BEGIN
      SELECT [object_id], [object_name] = @schemaName + '.' + name, [type], type_desc, parent_object_id,
             create_date, modify_date, is_ms_shipped
        FROM sys.objects
       WHERE [schema_id] = @schemaID AND LOWER(name) LIKE '%' + LOWER(@objectName) + '%'
       ORDER BY CASE [type] WHEN 'U' THEN '_A' WHEN 'V' THEN '_B' WHEN 'P' THEN '_C' WHEN 'FN' THEN '_D' WHEN 'IF' THEN '_E' WHEN 'PK' THEN '_F' ELSE [type] END,
                LOWER(name)
    END
  END
GO


IF OBJECT_ID('zdm.d') IS NOT NULL
  DROP SYNONYM zdm.d
GO
CREATE SYNONYM zdm.d FOR zdm.describe
GO


---------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.findusage') IS NOT NULL
  DROP PROCEDURE zdm.findusage
GO
CREATE PROCEDURE zdm.findusage
  @usageText  nvarchar(256),
  @describe   bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @objectID int, @objectName nvarchar(256), @text nvarchar(max), @somethingFound bit = 0

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT O.[object_id], S.name + '.' + O.name
          FROM sys.objects O
            INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
         WHERE O.is_ms_shipped = 0 AND O.type IN ('V', 'P', 'FN', 'IF') -- View, Procedure, Scalar Function, Table Function
         ORDER BY O.type_desc, S.name, O.name
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @objectID, @objectName
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @text = OBJECT_DEFINITION(@objectID)
    IF CHARINDEX(@usageText, @text) > 0
    BEGIN
      SET @somethingFound = 1

      IF @describe = 0
        PRINT @objectName
      ELSE
      BEGIN
        EXEC zdm.describe @objectName
        PRINT ''
        PRINT REPLICATE('#', 100)
      END
    END

    FETCH NEXT FROM @cursor INTO @objectID, @objectName
  END
  CLOSE @cursor
  DEALLOCATE @cursor

  IF @somethingFound = 0
    PRINT 'No usage found!'
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.info') IS NOT NULL
  DROP PROCEDURE zdm.info
GO
CREATE PROCEDURE zdm.info
  @info    varchar(100) = '',
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF @info = ''
  BEGIN
    PRINT 'AVAILABLE OPTIONS...'
    PRINT '  zdm.info ''tables'''
    PRINT '  zdm.info ''indexes'''
    PRINT '  zdm.info ''views'''
    PRINT '  zdm.info ''functions'''
    PRINT '  zdm.info ''procs'''
    PRINT '  zdm.info ''filegroups'''
    PRINT '  zdm.info ''mountpoints'''
    PRINT '  zdm.info ''partitions'''
    PRINT '  zdm.info ''index stats'''
    PRINT '  zdm.info ''proc stats'''
    PRINT '  zdm.info ''indexes by filegroup'''
    PRINT '  zdm.info ''indexes by allocation type'''
    RETURN
  END

  IF @filter != ''
    SET @filter = '%' + LOWER(@filter) + '%'

  IF @info = 'tables'
  BEGIN
    SELECT I.[object_id], [object_name] = S.name + '.' + O.name,
           [rows] = SUM(CASE WHEN I.index_id IN (0, 1) THEN P.row_count ELSE 0 END),
           total_kb = SUM(P.reserved_page_count * 8), used_kb = SUM(P.used_page_count * 8), data_kb = SUM(P.in_row_data_page_count * 8),
           create_date = MIN(CONVERT(datetime2(0), O.create_date)), modify_date = MIN(CONVERT(datetime2(0), O.modify_date))
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     GROUP BY I.[object_id], S.name, O.name
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'indexes'
  BEGIN
    SELECT I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(P.row_count),
           total_kb = SUM(P.reserved_page_count * 8), used_kb = SUM(P.used_page_count * 8), data_kb = SUM(P.in_row_data_page_count * 8),
           [partitions] = COUNT(*), I.fill_factor
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter))
     GROUP BY I.[object_id], I.index_id, I.type_desc, I.fill_factor, S.name, O.name, I.name
     ORDER BY S.name, O.name, I.index_id
  END

  ELSE IF @info = 'views'
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name,
           create_date = CONVERT(datetime2(0), O.create_date), modify_date = CONVERT(datetime2(0), O.modify_date)
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
     WHERE O.type_desc = 'VIEW'
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'functions'
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name, function_type = O.type_desc,
           create_date = CONVERT(datetime2(0), O.create_date), modify_date = CONVERT(datetime2(0), O.modify_date)
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
     WHERE O.type_desc IN ('SQL_SCALAR_FUNCTION', 'SQL_TABLE_VALUED_FUNCTION', 'SQL_INLINE_TABLE_VALUED_FUNCTION')
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(O.type_desc) LIKE @filter))
     ORDER BY S.name, O.name
  END

  ELSE IF @info IN ('procs', 'procedures')
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name,
           create_date = CONVERT(datetime2(0), O.create_date), modify_date = CONVERT(datetime2(0), O.modify_date)
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
     WHERE O.type_desc = 'SQL_STORED_PROCEDURE'
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'filegroups'
  BEGIN
    SELECT [filegroup] = F.name, total_kb = SUM(A.total_pages * 8), used_kb = SUM(A.used_pages * 8), data_kb = SUM(A.data_pages * 8)
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
        INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
          INNER JOIN sys.allocation_units A ON A.container_id = P.[partition_id]
            INNER JOIN sys.filegroups F ON F.data_space_id = A.data_space_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR LOWER(F.name) LIKE @filter)
     GROUP BY F.name
     ORDER BY F.name
  END

  ELSE IF @info = 'mountpoints'
  BEGIN
    SELECT DISTINCT volume_mount_point = UPPER(V.volume_mount_point), V.file_system_type, V.logical_volume_name,
           total_size_GB = CONVERT(DECIMAL(18,2), V.total_bytes / 1073741824.0),
           available_size_GB = CONVERT(DECIMAL(18,2), V.available_bytes / 1073741824.0),
           [space_free_%] = CONVERT(DECIMAL(18,2), CONVERT(float, V.available_bytes) / CONVERT(float, V.total_bytes)) * 100
      FROM sys.master_files AS F WITH (NOLOCK)
        CROSS APPLY sys.dm_os_volume_stats(F.database_id, F.file_id) AS V
     WHERE @filter = '' OR LOWER(V.volume_mount_point) LIKE @filter OR LOWER(V.logical_volume_name) LIKE @filter
     ORDER BY UPPER(V.volume_mount_point)
    OPTION (RECOMPILE);
  END

  ELSE IF @info = 'partitions'
  BEGIN
    SELECT I.[object_id], [object_name] = S.name + '.' + O.name, index_name = I.name, [filegroup_name] = F.name,
           partition_scheme = PS.name, partition_function = PF.name, P.partition_number, P.[rows], boundary_value = PRV.value,
           PF.boundary_value_on_right, [data_compression] = P.data_compression_desc
       FROM sys.partition_schemes PS
         INNER JOIN sys.indexes I ON I.data_space_id = PS.data_space_id
           INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
             INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
           INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
             INNER JOIN sys.destination_data_spaces DDS on DDS.partition_scheme_id = PS.data_space_id and DDS.destination_id = P.partition_number
               INNER JOIN sys.filegroups F ON F.data_space_id = DDS.data_space_id
         INNER JOIN sys.partition_functions PF ON PF.function_id = PS.function_id
           INNER JOIN sys.partition_range_values PRV on PRV.function_id = PF.function_id AND PRV.boundary_id = P.partition_number
     WHERE @filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter
     ORDER BY S.name, O.name, I.index_id, P.partition_number
  END

  ELSE IF @info = 'index stats'
  BEGIN
    SELECT I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(P.row_count),
           total_kb = SUM(P.reserved_page_count * 8),
           user_seeks = MAX(U.user_seeks), user_scans = MAX(U.user_scans), user_lookups = MAX(U.user_lookups), user_updates = MAX(U.user_updates),
           [partitions] = COUNT(*)
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
        LEFT JOIN sys.dm_db_index_usage_stats U ON U.database_id = DB_ID() AND U.[object_id] = I.[object_id] AND U.index_id = I.index_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter))
     GROUP BY I.[object_id], I.index_id, I.type_desc, S.name, O.name, I.name
     ORDER BY S.name, O.name, I.index_id
  END

  ELSE IF @info IN ('proc stats', 'procedure stats')
  BEGIN
    SELECT O.[object_id], [object_name] = S.name + '.' + O.name,
           P.execution_count, P.total_worker_time, P.total_elapsed_time, P.total_logical_reads, P.total_logical_writes,
           P.max_worker_time, P.max_elapsed_time, P.max_logical_reads, P.max_logical_writes,
           P.last_execution_time, P.cached_time
      FROM sys.objects O
        INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        LEFT JOIN sys.dm_exec_procedure_stats P ON P.database_id = DB_ID() AND P.[object_id] = O.[object_id]
     WHERE O.type_desc = 'SQL_STORED_PROCEDURE'
       AND (@filter = '' OR LOWER(S.name + '.' + O.name) LIKE @filter)
     ORDER BY S.name, O.name
  END

  ELSE IF @info = 'indexes by filegroup'
  BEGIN
    SELECT [filegroup] = F.name, I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(CASE WHEN A.type_desc = 'IN_ROW_DATA' THEN P.[rows] ELSE 0 END),
           total_kb = SUM(A.total_pages * 8), used_kb = SUM(A.used_pages * 8), data_kb = SUM(A.data_pages * 8),
           [partitions] = SUM(CASE WHEN A.type_desc = 'IN_ROW_DATA' THEN 1 ELSE 0 END),
           [compression] = CASE WHEN P.data_compression_desc = 'NONE' THEN '' ELSE P.data_compression_desc END
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
          INNER JOIN sys.allocation_units A ON A.container_id = P.[partition_id]
            INNER JOIN sys.filegroups F ON F.data_space_id = A.data_space_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter OR LOWER(F.name) LIKE @filter))
     GROUP BY F.name, I.[object_id], I.index_id, I.type_desc, S.name, O.name, I.name, P.data_compression_desc
     ORDER BY F.name, S.name, O.name, I.index_id
  END

  ELSE IF @info = 'indexes by allocation type'
  BEGIN
    SELECT allocation_type = A.type_desc,
           I.[object_id], I.index_id, index_type = I.type_desc, [object_name] = S.name + '.' + O.name, index_name = I.name,
           [rows] = SUM(CASE WHEN A.type_desc = 'IN_ROW_DATA' THEN P.[rows] ELSE 0 END),
           total_kb = SUM(A.total_pages * 8), used_kb = SUM(A.used_pages * 8), data_kb = SUM(A.data_pages * 8),
           [partitions] = COUNT(*),
           [compression] = CASE WHEN P.data_compression_desc = 'NONE' THEN '' ELSE P.data_compression_desc END,
           [filegroup] = F.name
      FROM sys.indexes I
        INNER JOIN sys.objects O ON O.[object_id] = I.[object_id]
          INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
        INNER JOIN sys.partitions P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
          INNER JOIN sys.allocation_units A ON A.container_id = P.[partition_id]
            INNER JOIN sys.filegroups F ON F.data_space_id = A.data_space_id
     WHERE O.type_desc = 'USER_TABLE' AND O.is_ms_shipped = 0
       AND (@filter = '' OR (LOWER(S.name + '.' + O.name) LIKE @filter OR LOWER(I.name) LIKE @filter OR LOWER(F.name) LIKE @filter OR LOWER(A.type_desc) LIKE @filter))
     GROUP BY A.type_desc, F.name, I.[object_id], I.index_id, I.type_desc, S.name, O.name, I.name, P.data_compression_desc
     ORDER BY A.type_desc, S.name, O.name, I.index_id
  END

  ELSE
  BEGIN
    PRINT 'OPTION NOT AVAILAIBLE !!!'
  END
GO


IF OBJECT_ID('zdm.i') IS NOT NULL
  DROP SYNONYM zdm.i
GO
CREATE SYNONYM zdm.i FOR zdm.info
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.filegroups') IS NOT NULL
  DROP PROCEDURE zdm.filegroups
GO
CREATE PROCEDURE zdm.filegroups
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC zdm.info 'filegroups', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.functions') IS NOT NULL
  DROP PROCEDURE zdm.functions
GO
CREATE PROCEDURE zdm.functions
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON

  EXEC zdm.info 'functions', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.indexes') IS NOT NULL
  DROP PROCEDURE zdm.indexes
GO
CREATE PROCEDURE zdm.indexes
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC zdm.info 'indexes', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.procs') IS NOT NULL
  DROP PROCEDURE zdm.procs
GO
CREATE PROCEDURE zdm.procs
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON

  EXEC zdm.info 'procs', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.tables') IS NOT NULL
  DROP PROCEDURE zdm.tables
GO
CREATE PROCEDURE zdm.tables
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON

  EXEC zdm.info 'tables', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.views') IS NOT NULL
  DROP PROCEDURE zdm.views
GO
CREATE PROCEDURE zdm.views
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC zdm.info 'views', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.partitions') IS NOT NULL
  DROP PROCEDURE zdm.partitions
GO
CREATE PROCEDURE zdm.partitions
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON

  EXEC zdm.info 'partitions', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.processinfo') IS NOT NULL
  DROP PROCEDURE zdm.processinfo
GO
CREATE PROCEDURE zdm.processinfo
  @hostName     nvarchar(100) = '',
  @programName  nvarchar(100) = ''
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF CONVERT(varchar, SERVERPROPERTY('productversion')) LIKE '10.%'
  BEGIN
    -- SQL 2008 does not have database_id in sys.dm_exec_sessions
    EXEC sp_executesql N'
      SELECT [db_name] = DB_NAME(P.[dbid]), S.[program_name], S.[host_name], S.host_process_id, S.login_name, session_count = COUNT(*)
        FROM sys.dm_exec_sessions S
          LEFT JOIN sys.sysprocesses P ON P.spid = S.session_id
       WHERE P.[dbid] != 0 AND S.[host_name] LIKE @hostName + ''%'' AND S.[program_name] LIKE @programName + ''%''
       GROUP BY DB_NAME(P.[dbid]), S.[program_name], S.[host_name], S.host_process_id, S.login_name
       ORDER BY [db_name], S.[program_name], S.login_name, COUNT(*) DESC, S.[host_name]', N'@hostName nvarchar(100), @programName nvarchar(100)', @hostName, @programName
  END
  ELSE
  BEGIN
    EXEC sp_executesql N'
      SELECT [db_name] = DB_NAME(database_id), [program_name], [host_name], host_process_id, login_name, session_count = COUNT(*)
        FROM sys.dm_exec_sessions
       WHERE database_id != 0 AND [host_name] LIKE @hostName + ''%'' AND [program_name] LIKE @programName + ''%''
       GROUP BY DB_NAME(database_id), [program_name], [host_name], host_process_id, login_name
       ORDER BY [db_name], [program_name], login_name, COUNT(*) DESC, [host_name]', N'@hostName nvarchar(100), @programName nvarchar(100)', @hostName, @programName
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.sessioninfo') IS NOT NULL
  DROP PROCEDURE zdm.sessioninfo
GO
CREATE PROCEDURE zdm.sessioninfo
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF CONVERT(varchar, SERVERPROPERTY('productversion')) LIKE '10.%'
  BEGIN
    -- SQL 2008 does not have database_id in sys.dm_exec_sessions
    EXEC sp_executesql N'
      SELECT [db_name] = DB_NAME(P.[dbid]), S.[program_name], S.login_name,
             host_count = COUNT(DISTINCT S.[host_name]),
             process_count = COUNT(DISTINCT S.[host_name] + CONVERT(nvarchar, S.host_process_id)),
             session_count = COUNT(*)
        FROM sys.dm_exec_sessions S
          LEFT JOIN sys.sysprocesses P ON P.spid = S.session_id
       WHERE P.[dbid] != 0
       GROUP BY DB_NAME(P.[dbid]), S.[program_name], S.login_name
       ORDER BY COUNT(*) DESC'
  END
  ELSE
  BEGIN
    EXEC sp_executesql N'
      SELECT [db_name] = DB_NAME(database_id), [program_name], login_name,
             host_count = COUNT(DISTINCT [host_name]),
             process_count = COUNT(DISTINCT [host_name] + CONVERT(nvarchar, host_process_id)),
             session_count = COUNT(*)
        FROM sys.dm_exec_sessions
       WHERE database_id != 0
       GROUP BY DB_NAME(database_id), [program_name], login_name
       ORDER BY COUNT(*) DESC'
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.StartTrace') IS NOT NULL
  DROP PROCEDURE zdm.StartTrace
GO
CREATE PROCEDURE zdm.StartTrace
  @fileName         nvarchar(200),
  @minutes          smallint,
  @duration         bigint = NULL,
  @reads            bigint = NULL,
  @writes           bigint = NULL,
  @cpu              int = NULL,
  @rowCounts        bigint = NULL,
  @objectName       nvarchar(100) = NULL,
  @hostName         nvarchar(100) = NULL,
  @clientProcessID  nvarchar(100) = NULL,
  @databaseName     nvarchar(100) = NULL,
  @loginName        nvarchar(100) = NULL,
  @logicalOperator  int = 0,
  @maxFileSize      bigint = 4096
AS
  SET NOCOUNT ON

  -- Create trace
  DECLARE @rc int, @traceID int, @stopTime datetime2(0)
  SET @stopTime = DATEADD(minute, @minutes, GETDATE())
  EXEC @rc = sp_trace_create @traceID OUTPUT, 0, @fileName, @maxFileSize, @stopTime
  IF @rc != 0
  BEGIN
    RAISERROR ('Error in sp_trace_create (ErrorCode = %d)', 16, 1, @rc)
    RETURN -1
  END

  -- Event: RPC:Completed
  DECLARE @off bit, @on bit
  SELECT @off = 0, @on = 1
  EXEC sp_trace_setevent @traceID, 10, 14, @on  -- StartTime
  EXEC sp_trace_setevent @traceID, 10, 15, @on  -- EndTime
  EXEC sp_trace_setevent @traceID, 10, 34, @on  -- ObjectName
  EXEC sp_trace_setevent @traceID, 10,  1, @on  -- TextData
  EXEC sp_trace_setevent @traceID, 10, 13, @on  -- Duration
  EXEC sp_trace_setevent @traceID, 10, 16, @on  -- Reads
  EXEC sp_trace_setevent @traceID, 10, 17, @on  -- Writes
  EXEC sp_trace_setevent @traceID, 10, 18, @on  -- CPU
  EXEC sp_trace_setevent @traceID, 10, 48, @on  -- RowCounts
  EXEC sp_trace_setevent @traceID, 10,  8, @on  -- HostName
  EXEC sp_trace_setevent @traceID, 10,  9, @on  -- ClientProcessID
  EXEC sp_trace_setevent @traceID, 10, 12, @on  -- SPID
  EXEC sp_trace_setevent @traceID, 10, 10, @on  -- ApplicationName
  EXEC sp_trace_setevent @traceID, 10, 11, @on  -- LoginName
  EXEC sp_trace_setevent @traceID, 10, 35, @on  -- DatabaseName
  EXEC sp_trace_setevent @traceID, 10, 31, @on  -- Error

  -- Event: SQL:BatchCompleted
  IF @objectName IS NULL
  BEGIN
    EXEC sp_trace_setevent @traceID, 12, 14, @on  -- StartTime
    EXEC sp_trace_setevent @traceID, 12, 15, @on  -- EndTime
    EXEC sp_trace_setevent @traceID, 12, 34, @on  -- ObjectName
    EXEC sp_trace_setevent @traceID, 12,  1, @on  -- TextData
    EXEC sp_trace_setevent @traceID, 12, 13, @on  -- Duration
    EXEC sp_trace_setevent @traceID, 12, 16, @on  -- Reads
    EXEC sp_trace_setevent @traceID, 12, 17, @on  -- Writes
    EXEC sp_trace_setevent @traceID, 12, 18, @on  -- CPU
    EXEC sp_trace_setevent @traceID, 12, 48, @on  -- RowCounts
    EXEC sp_trace_setevent @traceID, 12,  8, @on  -- HostName
    EXEC sp_trace_setevent @traceID, 12,  9, @on  -- ClientProcessID
    EXEC sp_trace_setevent @traceID, 12, 12, @on  -- SPID
    EXEC sp_trace_setevent @traceID, 12, 10, @on  -- ApplicationName
    EXEC sp_trace_setevent @traceID, 12, 11, @on  -- LoginName
    EXEC sp_trace_setevent @traceID, 12, 35, @on  -- DatabaseName
    EXEC sp_trace_setevent @traceID, 12, 31, @on  -- Error
  END

  -- Filter: Duration
  IF @duration > 0
  BEGIN
    SET @duration = @duration * 1000
    EXEC sp_trace_setfilter @traceID, 13, @logicalOperator, 4, @duration
  END
  -- Filter: Reads
  IF @reads > 0
    EXEC sp_trace_setfilter @traceID, 16, @logicalOperator, 4, @reads
  -- Filter: Writes
  IF @writes > 0
    EXEC sp_trace_setfilter @traceID, 17, @logicalOperator, 4, @writes
  -- Filter: CPU
  IF @cpu > 0
    EXEC sp_trace_setfilter @traceID, 18, @logicalOperator, 4, @cpu
  -- Filter: RowCounts
  IF @rowCounts > 0
    EXEC sp_trace_setfilter @traceID, 48, @logicalOperator, 4, @rowCounts
  -- Filter: ObjectName
  IF @objectName IS NOT NULL
    EXEC sp_trace_setfilter @traceID, 34, @logicalOperator, 6, @objectName
  -- Filter: HostName
  IF @hostName IS NOT NULL
    EXEC sp_trace_setfilter @traceID, 8, @logicalOperator, 6, @hostName
  -- Filter: ClientProcessID
  IF @clientProcessID > 0
    EXEC sp_trace_setfilter @traceID, 9, @logicalOperator, 0, @clientProcessID
  -- Filter: DatabaseName
  IF @databaseName IS NOT NULL
    EXEC sp_trace_setfilter @traceID, 35, @logicalOperator, 6, @databaseName
  -- Filter: LoginName
  IF @loginName IS NOT NULL
    EXEC sp_trace_setfilter @traceID, 11, @logicalOperator, 6, @loginName

  -- Start trace
  EXEC sp_trace_setstatus @traceID, 1

  -- Return traceID and some extra help info
  SELECT traceID = @traceID,
         [To list active traces] = 'SELECT * FROM sys.traces',
         [To stop trace before minutes are up] = 'EXEC sp_trace_setstatus ' + CONVERT(varchar, @traceID) + ', 0;EXEC sp_trace_setstatus ' + CONVERT(varchar, @traceID) + ', 2'
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000001001)
  INSERT INTO zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000001001, 'Task started', '')
IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000001002)
  INSERT INTO zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000001002, 'Task info', '')
IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000001003)
  INSERT INTO zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000001003, 'Task completed', '')
IF NOT EXISTS(SELECT * FROM zsystem.eventTypes WHERE eventTypeID = 2000001004)
  INSERT INTO zsystem.eventTypes (eventTypeID, eventTypeName, [description])
       VALUES (2000001004, 'Task ERROR', '')
GO


---------------------------------------------------------------------------------------------------------------------------------


-- *** taskID under 100 mills are reserved for fixed taskID's                                                    ***
-- *** taksID over 100 mills are automagically generated from taskName if taskName used not found over 100 mills ***

IF OBJECT_ID('zsystem.tasks') IS NULL
BEGIN
  CREATE TABLE zsystem.tasks
  (
    taskID         int                                          NOT NULL,
    taskName       nvarchar(450)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]  nvarchar(max)                                NULL,
    --
    CONSTRAINT tasks_PK PRIMARY KEY CLUSTERED (taskID)
  )

  CREATE NONCLUSTERED INDEX tasks_IX_Name ON zsystem.tasks (taskName)
END
GRANT SELECT ON zsystem.tasks TO zzp_server
GO


IF NOT EXISTS(SELECT * FROM zsystem.tasks WHERE taskID = 100000000)
  INSERT INTO zsystem.tasks (taskID, taskName, [description])
       VALUES (100000000, 'DUMMY TASK - 100 MILLS', 'A dummy task to make MAX(taskID) start over 100 mills')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_Insert') IS NOT NULL
  DROP PROCEDURE zsystem.Events_Insert
GO
CREATE PROCEDURE zsystem.Events_Insert
  @eventTypeID  int,
  @duration     int = NULL,
  @int_1        int = NULL,
  @int_2        int = NULL,
  @int_3        int = NULL,
  @int_4        int = NULL,
  @int_5        int = NULL,
  @int_6        int = NULL,
  @int_7        int = NULL,
  @int_8        int = NULL,
  @int_9        int = NULL,
  @eventText    nvarchar(max) = NULL,
  @returnRow    bit = 0,
  @referenceID  int = NULL,
  @date_1       date = NULL,
  @taskID       int = NULL,
  @textID       int = NULL,
  @fixedText    nvarchar(450) = NULL,
  @nestLevel    tinyint = NULL,
  @parentID     int = NULL
AS
  SET NOCOUNT ON

  DECLARE @eventID int

  IF @textID IS NULL AND @fixedText IS NOT NULL
    EXEC @textID = zsystem.Texts_ID @fixedText

  INSERT INTO zsystem.events
              (eventTypeID, duration, int_1, int_2, int_3, int_4, int_5, int_6, int_7, int_8, int_9, eventText, referenceID, date_1, taskID, textID, nestLevel, parentID)
       VALUES (@eventTypeID, @duration, @int_1, @int_2, @int_3, @int_4, @int_5, @int_6, @int_7, @int_8, @int_9, @eventText, @referenceID, @date_1, @taskID, @textID, @nestLevel, @parentID)

  SET @eventID = SCOPE_IDENTITY()

  IF @returnRow = 1
    SELECT eventID = @eventID

  RETURN @eventID
GO
GRANT EXEC ON zsystem.Events_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Tasks_DynamicID') IS NOT NULL
  DROP PROCEDURE zsystem.Tasks_DynamicID
GO
CREATE PROCEDURE zsystem.Tasks_DynamicID
  @taskName  nvarchar(450)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @taskID int
  SELECT @taskID = taskID FROM zsystem.tasks WHERE taskName = @taskName AND taskID > 100000000
  IF @taskID IS NULL
  BEGIN
    SELECT @taskID = MAX(taskID) + 1 FROM zsystem.tasks

    INSERT INTO zsystem.tasks (taskID, taskName) VALUES (@taskID, @taskName)
  END
  RETURN @taskID
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.eventsEx') IS NOT NULL
  DROP VIEW zsystem.eventsEx
GO
CREATE VIEW zsystem.eventsEx
AS
  SELECT E.eventID, E.eventDate, E.eventTypeID, ET.eventTypeName, E.taskID, T.taskName, fixedText = X.[text], E.eventText,
         E.duration, E.referenceID, E.parentID, E.nestLevel,
         E.date_1, E.int_1, E.int_2, E.int_3, E.int_4, E.int_5, E.int_6, E.int_7, E.int_8, E.int_9
    FROM zsystem.events E
      LEFT JOIN zsystem.eventTypes ET ON ET.eventTypeID = E.eventTypeID
      LEFT JOIN zsystem.tasks T ON T.taskID = E.taskID
      LEFT JOIN zsystem.texts X ON X.textID = E.textID
GO
GRANT SELECT ON zsystem.eventsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_TaskStarted') IS NOT NULL
  DROP PROCEDURE zsystem.Events_TaskStarted
GO
CREATE PROCEDURE zsystem.Events_TaskStarted
  @taskName     nvarchar(450) = NULL,
  @fixedText    nvarchar(450) = NULL,
  @eventText    nvarchar(max) = NULL,
  @int_1        int = NULL,
  @int_2        int = NULL,
  @int_3        int = NULL,
  @int_4        int = NULL,
  @int_5        int = NULL,
  @int_6        int = NULL,
  @int_7        int = NULL,
  @int_8        int = NULL,
  @int_9        int = NULL,
  @date_1       date = NULL,
  @taskID       int = NULL,
  @eventTypeID  int = 2000001001,
  @returnRow    bit = 0,
  @parentID     int = NULL
AS
  SET NOCOUNT ON

  IF @taskID IS NULL AND @taskName IS NOT NULL
    EXEC @taskID = zsystem.Tasks_DynamicID @taskName

  DECLARE @nestLevel int
  SET @nestLevel = @@NESTLEVEL - 1
  IF @nestLevel < 1 SET @nestLevel = NULL
  IF @nestLevel > 255 SET @nestLevel = 255

  DECLARE @eventID int

  EXEC @eventID = zsystem.Events_Insert @eventTypeID, NULL, @int_1, @int_2, @int_3, @int_4, @int_5, @int_6, @int_7, @int_8, @int_9, @eventText, @returnRow, NULL, @date_1, @taskID, NULL, @fixedText, @nestLevel, @parentID

  RETURN @eventID
GO
GRANT EXEC ON zsystem.Events_TaskStarted TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_TaskCompleted') IS NOT NULL
  DROP PROCEDURE zsystem.Events_TaskCompleted
GO
CREATE PROCEDURE zsystem.Events_TaskCompleted
  @eventID      int = NULL,
  @eventText    nvarchar(max) = NULL,
  @int_1        int = NULL,
  @int_2        int = NULL,
  @int_3        int = NULL,
  @int_4        int = NULL,
  @int_5        int = NULL,
  @int_6        int = NULL,
  @int_7        int = NULL,
  @int_8        int = NULL,
  @int_9        int = NULL,
  @date_1       date = NULL,
  @taskID       int = NULL,
  @taskName     nvarchar(450) = NULL,
  @fixedText    nvarchar(450) = NULL,
  @duration     int = NULL,
  @eventTypeID  int = 2000001003,
  @returnRow    bit = 0
AS
  SET NOCOUNT ON

  DECLARE @textID int, @nestLevel tinyint, @parentID int

  IF @eventID IS NOT NULL AND @taskID IS NULL AND @duration IS NULL
  BEGIN
    DECLARE @eventDate datetime2(0)
    SELECT @taskID = taskID, @textID = textID, @eventDate = eventDate, @nestLevel = nestLevel, @parentID = parentID FROM zsystem.events WHERE eventID = @eventID
    IF @eventDate IS NOT NULL
    BEGIN
      SET @duration = DATEDIFF(second, @eventDate, GETUTCDATE())
      IF @duration < 0 SET @duration = 0
    END
  END

  IF @taskID IS NULL AND @taskName IS NOT NULL
    EXEC @taskID = zsystem.Tasks_DynamicID @taskName

  IF @fixedText IS NOT NULL
    SET @textID = NULL

  EXEC @eventID = zsystem.Events_Insert @eventTypeID, @duration, @int_1, @int_2, @int_3, @int_4, @int_5, @int_6, @int_7, @int_8, @int_9, @eventText, @returnRow, @eventID, @date_1, @taskID, @textID, @fixedText, @nestLevel, @parentID

  RETURN @eventID
GO
GRANT EXEC ON zsystem.Events_TaskCompleted TO zzp_server
GO



---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_TaskInfo') IS NOT NULL
  DROP PROCEDURE zsystem.Events_TaskInfo
GO
CREATE PROCEDURE zsystem.Events_TaskInfo
  @eventID      int = NULL,
  @eventText    nvarchar(max) = NULL,
  @int_1        int = NULL,
  @int_2        int = NULL,
  @int_3        int = NULL,
  @int_4        int = NULL,
  @int_5        int = NULL,
  @int_6        int = NULL,
  @int_7        int = NULL,
  @int_8        int = NULL,
  @int_9        int = NULL,
  @date_1       date = NULL,
  @taskID       int = NULL,
  @taskName     nvarchar(450) = NULL,
  @fixedText    nvarchar(450) = NULL,
  @eventTypeID  int = 2000001002,
  @returnRow    bit = 0
AS
  SET NOCOUNT ON

  DECLARE @textID int, @nestLevel tinyint, @parentID int

  IF @eventID IS NOT NULL AND @taskID IS NULL
    SELECT @taskID = taskID, @textID = textID, @nestLevel = nestLevel, @parentID = parentID FROM zsystem.events WHERE eventID = @eventID

  IF @taskID IS NULL AND @taskName IS NOT NULL
    EXEC @taskID = zsystem.Tasks_DynamicID @taskName

  IF @fixedText IS NOT NULL
    SET @textID = NULL

  EXEC @eventID = zsystem.Events_Insert @eventTypeID, NULL, @int_1, @int_2, @int_3, @int_4, @int_5, @int_6, @int_7, @int_8, @int_9, @eventText, @returnRow, @eventID, @date_1, @taskID, @textID, @fixedText, @nestLevel, @parentID

  RETURN @eventID
GO
GRANT EXEC ON zsystem.Events_TaskInfo TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_TaskError') IS NOT NULL
  DROP PROCEDURE zsystem.Events_TaskError
GO
CREATE PROCEDURE zsystem.Events_TaskError
  @eventID      int = NULL,
  @eventText    nvarchar(max) = NULL,
  @int_1        int = NULL,
  @int_2        int = NULL,
  @int_3        int = NULL,
  @int_4        int = NULL,
  @int_5        int = NULL,
  @int_6        int = NULL,
  @int_7        int = NULL,
  @int_8        int = NULL,
  @int_9        int = NULL,
  @date_1       date = NULL,
  @taskID       int = NULL,
  @taskName     nvarchar(450) = NULL,
  @fixedText    nvarchar(450) = NULL,
  @duration     int = NULL,
  @eventTypeID  int = 2000001004,
  @returnRow    bit = 0,
  @taskEnded    bit = 1
AS
  SET NOCOUNT ON

  DECLARE @textID int, @nestLevel tinyint, @parentID int

  IF @eventID IS NOT NULL AND @taskID IS NULL AND @duration IS NULL
  BEGIN
    DECLARE @eventDate datetime2(0)
    SELECT @taskID = taskID, @textID = textID, @eventDate = eventDate, @nestLevel = nestLevel, @parentID = parentID FROM zsystem.events WHERE eventID = @eventID
    IF @eventDate IS NOT NULL AND @taskEnded = 1
    BEGIN
      SET @duration = DATEDIFF(second, @eventDate, GETUTCDATE())
      IF @duration < 0 SET @duration = 0
    END
  END

  IF @taskID IS NULL AND @taskName IS NOT NULL
    EXEC @taskID = zsystem.Tasks_DynamicID @taskName

  IF @fixedText IS NOT NULL
    SET @textID = NULL

  EXEC @eventID = zsystem.Events_Insert @eventTypeID, @duration, @int_1, @int_2, @int_3, @int_4, @int_5, @int_6, @int_7, @int_8, @int_9, @eventText, @returnRow, @eventID, @date_1, @taskID, @textID, @fixedText, @nestLevel, @parentID

  RETURN @eventID
GO
GRANT EXEC ON zsystem.Events_TaskError TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_JobInfo') IS NOT NULL
  DROP PROCEDURE zsystem.Events_JobInfo
GO
CREATE PROCEDURE zsystem.Events_JobInfo
  @jobID        int,
  @fixedText    nvarchar(450) = NULL,
  @eventText    nvarchar(max) = NULL,
  @int_2        int = NULL,
  @int_3        int = NULL,
  @int_4        int = NULL,
  @int_5        int = NULL,
  @int_6        int = NULL,
  @int_7        int = NULL,
  @int_8        int = NULL,
  @int_9        int = NULL,
  @date_1       date = NULL
AS
  SET NOCOUNT ON

  DECLARE @taskName nvarchar(450)
  SELECT @taskName = jobName FROM zsystem.jobs WHERE jobID = @jobID

  DECLARE @eventID int

  EXEC @eventID = zsystem.Events_TaskInfo NULL, @eventText, @jobID, @int_2, @int_3, @int_4, @int_5, @int_6, @int_7, @int_8, @int_9, @date_1, NULL, @taskName, @fixedText, 2000000022

  RETURN @eventID
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Jobs_Exec') IS NOT NULL
  DROP PROCEDURE zsystem.Jobs_Exec
GO
CREATE PROCEDURE zsystem.Jobs_Exec
  @group  nvarchar(100) = 'SCHEDULE',
  @part   smallint = NULL
AS
  -- This proc must be called every 10 minutes in a SQL Agent job, no more and no less
  -- @part...
  --   NULL: Use hour:minute (typically used for group SCHEDULE)
  --      0: Execute all parts (typically used for group DOWNTIME)
  --     >0: Execute only that part (typically used for group DOWNTIME)
  -- When @part is NULL...
  --   If week/day/hour/minute is NULL job executes every time the proc is called (every 10 minutes)
  --   If week/day/hour is NULL job executes every hour on the minutes set
  SET NOCOUNT ON

  DECLARE @now datetime2(0), @day tinyint
  SELECT @now = GETUTCDATE(), @day = DATEPART(weekday, @now)

  DECLARE @week tinyint, @r real
  SET @r = DAY(@now) / 7.0
  IF @r <= 1.0 SET @week = 1
  ELSE IF @r <= 2.0 SET @week = 2
  ELSE IF @r <= 3.0 SET @week = 3
  ELSE IF @r <= 4.0 SET @week = 4

  DECLARE @jobID int, @jobName nvarchar(200), @sql nvarchar(max), @logStarted bit, @logCompleted bit, @eventID int, @eventText nvarchar(max)

  DECLARE @cursor CURSOR

  IF @part IS NULL
  BEGIN
    DECLARE @hour tinyint, @minute tinyint
    SELECT @hour = DATEPART(hour, @now), @minute = (DATEPART(minute, @now) / 10) * 10

    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT jobID, jobName, [sql], logStarted, logCompleted
            FROM zsystem.jobs
           WHERE [group] = @group AND [disabled] = 0 AND
                 (([week] IS NULL AND [day] IS NULL AND [hour] IS NULL AND [minute] IS NULL)
                  OR
                  ([week] IS NULL AND [day] IS NULL AND [hour] IS NULL AND [minute] = @minute)
                  OR
                  ([hour] = @hour AND [minute] = @minute AND ([day] IS NULL OR [day] = @day) AND ([week] IS NULL OR [week] = @week)))
           ORDER BY orderID
  END
  ELSE IF @part = 0
  BEGIN
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT jobID, jobName, [sql], logStarted, logCompleted
            FROM zsystem.jobs
           WHERE [group] = @group AND [disabled] = 0 AND
                 ([day] IS NULL OR [day] = @day) AND ([week] IS NULL OR [week] = @week)
           ORDER BY part, orderID
  END
  ELSE
  BEGIN
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT jobID, jobName, [sql], logStarted, logCompleted
            FROM zsystem.jobs
           WHERE [group] = @group AND part = @part AND [disabled] = 0 AND
                 ([day] IS NULL OR [day] = @day) AND ([week] IS NULL OR [week] = @week)
           ORDER BY part, orderID
  END

  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @jobID, @jobName, @sql, @logStarted, @logCompleted
  WHILE @@FETCH_STATUS = 0
  BEGIN
    -- Job started event
    IF @logStarted = 1
      EXEC @eventID = zsystem.Events_TaskStarted @jobName, @int_1=@jobID, @eventTypeID=2000000021

    -- Job execute 
    BEGIN TRY
      EXEC sp_executesql @sql
    END TRY
    BEGIN CATCH
      -- Job ERROR event
      SET @eventText = ERROR_MESSAGE()
      EXEC zsystem.Events_TaskError @eventID, @eventText, @int_1=@jobID, @eventTypeID=2000000024

      DECLARE @objectName nvarchar(256)
      SET @objectName = 'zsystem.Jobs_Exec: ' + @jobName
      EXEC zsystem.CatchError @objectName
    END CATCH

    -- Job completed event
    IF @logCompleted = 1
      EXEC zsystem.Events_TaskCompleted @eventID, @int_1=@jobID, @eventTypeID=2000000023

    FETCH NEXT FROM @cursor INTO @jobID, @jobName, @sql, @logStarted, @logCompleted
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Columns_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Columns_Select
GO
CREATE PROCEDURE zsystem.Columns_Select
  @schemaName  nvarchar(128),
  @tableName   nvarchar(128),
  @tableID     int = NULL
AS
  SET NOCOUNT ON

  IF @tableID IS NULL SET @tableID = zsystem.Tables_ID(@schemaName, @tableName)

  -- Using COLLATE so SQL works on Azure
  SELECT columnName = c.[name], c.system_type_id, c.max_length, c.is_nullable,
         c2.[readonly], c2.lookupTable, c2.lookupID, c2.lookupName, c2.lookupWhere, c2.html, c2.localizationGroupID
    FROM sys.columns c
      LEFT JOIN zsystem.columns c2 ON c2.tableID = @tableID AND c2.columnName COLLATE Latin1_General_BIN = c.[name] COLLATE Latin1_General_BIN
   WHERE c.[object_id] = OBJECT_ID(@schemaName + '.' + @tableName) AND ISNULL(c2.obsolete, 0) = 0
   ORDER BY c.column_id
GO
GRANT EXEC ON zsystem.Columns_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Intervals_OverflowAlert') IS NOT NULL
  DROP PROCEDURE zsystem.Intervals_OverflowAlert
GO
CREATE PROCEDURE zsystem.Intervals_OverflowAlert
  @alertLevel  real = 0.05 -- default alert level (we alert when less than 5% of the ids are left)
AS
  SET NOCOUNT ON

  IF EXISTS (SELECT * FROM zsystem.intervals WHERE (maxID - currentID) / CONVERT(real, (maxID - minID)) <= @alertLevel)
  BEGIN
    DECLARE @recipients varchar(max)
    SET @recipients = zsystem.Settings_Value('zsystem', 'Recipients-Operations-Software')

    IF @recipients != '' AND zsystem.Settings_Value('zsystem', 'Database') = DB_NAME()
    BEGIN
      DECLARE @intervalID int
      DECLARE @intervalName nvarchar(400)
      DECLARE @maxID int
      DECLARE @currentID int
      DECLARE @body nvarchar(max)

      DECLARE @cursor CURSOR
      SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT intervalID, intervalName, maxID, currentID
            FROM zsystem.intervals
           WHERE (maxID - currentID) / CONVERT(real, (maxID - minID)) <= @alertLevel
      OPEN @cursor
      FETCH NEXT FROM @cursor INTO @intervalID, @intervalName, @maxID, @currentID
      WHILE @@FETCH_STATUS = 0
      BEGIN
        SET @body = N'ID''s for the interval: <b>' + @intervalName  + N' (intervalID: '
                  + CONVERT(nvarchar, @intervalID) + N')</b> is getting low.<br>'
                  + N'The current counter is now at ' + CONVERT(nvarchar, @currentID) + N' and the maximum it can '
                  + N'get up to is ' + CONVERT(nvarchar, @maxID) + N', so we will run out after '
                  + CONVERT(nvarchar, (@maxID-@currentID)) + N' ID''s.<br><br>'
                  + N'We need to find another range for it very soon, so please don''t just ignore this mail! <br><br>'
                  + N'That was all <br>  Your friendly automatic e-mail sender'

        EXEC zsystem.SendMail @recipients, 'INTERVAL OVERFLOW ALERT!', @body, 'HTML'
        FETCH NEXT FROM @cursor INTO @intervalID, @intervalName, @maxID, @currentID
      END
      CLOSE @cursor
      DEALLOCATE @cursor
    END
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_Insert') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_Insert
GO
CREATE PROCEDURE zmetric.Counters_Insert
  @counterType           char(1) = 'D',         -- C:Column, D:Date, S:Simple, T:Time
  @counterID             smallint = NULL,       -- NULL means MAX-UNDER-30000 + 1
  @counterName           nvarchar(200),
  @groupID               smallint = NULL,
  @description           nvarchar(max) = NULL,
  @subjectLookupTableID  int = NULL,            -- Lookup table for subjectID, pointing to zsystem.lookupTables/Values
  @keyLookupTableID      int = NULL,            -- Lookup table for keyID, pointing to zsystem.lookupTables/Values
  @source                nvarchar(200) = NULL,  -- Description of data source, f.e. table name
  @subjectID             nvarchar(200) = NULL,  -- Description of subjectID column
  @keyID                 nvarchar(200) = NULL,  -- Description of keyID column
  @absoluteValue         bit = 0,               -- If set counter stores absolute value
  @shortName             nvarchar(50) = NULL,
  @order                 smallint = 0,
  @procedureName         nvarchar(500) = NULL,  -- Procedure called to get data for the counter
  @procedureOrder        tinyint = 255,
  @parentCounterID       smallint = NULL,
  @baseCounterID         smallint = NULL,
  @counterIdentifier     varchar(500) = NULL,
  @published             bit = 1,
  @sourceType            varchar(20) = NULL,    -- Used f.e. on EVE Metrics to say if counter comes from DB or DOOBJOB
  @units                 varchar(20) = NULL,
  @counterTable          nvarchar(256) = NULL,
  @userName              varchar(200) = NULL
AS
  SET NOCOUNT ON

  IF @counterID IS NULL
    SELECT @counterID = MAX(counterID) + 1 FROM zmetric.counters WHERE counterID < 30000
  IF @counterID IS NULL SET @counterID = 1

  IF @counterIdentifier IS NULL SET @counterIdentifier = @counterID

  INSERT INTO zmetric.counters
              (counterID, counterName, groupID, [description], subjectLookupTableID, keyLookupTableID, [source], subjectID, keyID,
               absoluteValue, shortName, [order], procedureName, procedureOrder, parentCounterID, baseCounterID, counterType,
               counterIdentifier, published, sourceType, units, counterTable, userName)
       VALUES (@counterID, @counterName, @groupID, @description, @subjectLookupTableID, @keyLookupTableID, @source, @subjectID, @keyID,
               @absoluteValue, @shortName, @order, @procedureName, @procedureOrder, @parentCounterID, @baseCounterID, @counterType,
               @counterIdentifier, @published, @sourceType, @units, @counterTable, @userName)

  SELECT counterID = @counterID
GO
GRANT EXEC ON zmetric.Counters_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_ReportDates') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_ReportDates
GO
CREATE PROCEDURE zmetric.Counters_ReportDates
  @counterID      smallint,
  @counterDate    date = NULL,
  @seek           char(1) = NULL -- NULL / O:Older / N:Newer
AS
  -- Get date to use for zmetric.Counters_ReportData
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @counterID IS NULL
      RAISERROR ('@counterID not set', 16, 1)

    IF @seek IS NOT NULL AND @seek NOT IN ('O', 'N')
      RAISERROR ('Only seek types O and N are supported', 16, 1)

    DECLARE @counterTable nvarchar(256), @counterType char(1)
    SELECT @counterTable = counterTable, @counterType = counterType FROM zmetric.counters  WHERE counterID = @counterID
    IF @counterTable IS NULL AND @counterType = 'D'
        SET @counterTable = 'zmetric.dateCounters'
    IF @counterTable IS NULL OR @counterTable NOT IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters', 'zmetric.dateCounters')
      RAISERROR ('Counter table not supported', 16, 1)

    DECLARE @dateRequested date, @dateReturned date

    IF @counterDate IS NULL
    BEGIN
      SET @dateRequested = DATEADD(day, -1, GETDATE())

      IF @counterTable = 'zmetric.dateCounters'
        SELECT TOP 1 @dateReturned = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate <= @dateRequested ORDER BY counterDate DESC
      ELSE IF @counterTable = 'zmetric.subjectKeyCounters'
        SELECT TOP 1 @dateReturned = counterDate FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate <= @dateRequested ORDER BY counterDate DESC
      ELSE
        SELECT TOP 1 @dateReturned = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate <= @dateRequested ORDER BY counterDate DESC
    END
    ELSE
    BEGIN
      SET @dateRequested = @counterDate

      IF @seek IS NULL
        SET @dateReturned = @counterDate
      ELSE
      BEGIN
        IF @counterTable = 'zmetric.dateCounters'
        BEGIN
          IF NOT EXISTS(SELECT * FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate = @counterDate)
          BEGIN
            IF @seek = 'O'
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate < @counterDate ORDER BY counterDate DESC
            ELSE
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate > @counterDate ORDER BY counterDate
          END
        END
        ELSE IF @counterTable = 'zmetric.subjectKeyCounters'
        BEGIN
          IF NOT EXISTS(SELECT * FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate = @counterDate)
          BEGIN
            IF @seek = 'O'
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate < @counterDate ORDER BY counterDate DESC
            ELSE
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate > @counterDate ORDER BY counterDate
          END
        END
        ELSE
        BEGIN
          IF NOT EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate = @counterDate)
          BEGIN
            IF @seek = 'O'
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate < @counterDate ORDER BY counterDate DESC
            ELSE
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate > @counterDate ORDER BY counterDate
          END
        END
      END
    END

    IF @dateReturned IS NULL
      SET @dateReturned = @dateRequested

    SELECT dateRequested = @dateRequested, dateReturned = @dateReturned
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.Counters_ReportDates'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zmetric.Counters_ReportDates TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_ReportData') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_ReportData
GO
CREATE PROCEDURE zmetric.Counters_ReportData
  @counterID      smallint,
  @fromDate       date = NULL,
  @toDate         date = NULL,
  @rows           int = 20,
  @orderColumnID  smallint = NULL,
  @orderDesc      bit = 1,
  @lookupText     nvarchar(1000) = NULL
AS
  -- Create dynamic SQL to return report used on INFO - Metrics
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @counterID IS NULL
      RAISERROR ('@counterID not set', 16, 1)

    IF @fromDate IS NULL
      RAISERROR ('@fromDate not set', 16, 1)

    IF @rows > 10000
      RAISERROR ('@rows over limit', 16, 1)

    IF @toDate IS NOT NULL AND @toDate = @fromDate
      SET @toDate = NULL

    DECLARE @counterTable nvarchar(256), @counterType char(1), @subjectLookupTableID int, @keyLookupTableID int
    SELECT @counterTable = counterTable, @counterType = counterType, @subjectLookupTableID = subjectLookupTableID, @keyLookupTableID = keyLookupTableID
      FROM zmetric.counters
     WHERE counterID = @counterID
    IF @counterTable IS NULL AND @counterType = 'D'
      SET @counterTable = 'zmetric.dateCounters'
    IF @counterTable IS NULL OR @counterTable NOT IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters', 'zmetric.dateCounters')
      RAISERROR ('Counter table not supported', 16, 1)
    IF @subjectLookupTableID IS NOT NULL AND @keyLookupTableID IS NULL
      RAISERROR ('Counter is not valid, subject lookup set and key lookup not set', 16, 1)
    IF @counterTable = 'zmetric.keyCounters' AND @subjectLookupTableID IS NOT NULL
      RAISERROR ('Key counter is not valid, subject lookup set', 16, 1)
    IF @counterTable = 'zmetric.subjectKeyCounters' AND (@subjectLookupTableID IS NULL OR @keyLookupTableID IS NULL)
      RAISERROR ('Subject/Key counter is not valid, subject lookup or key lookup not set', 16, 1)

    DECLARE @sql nvarchar(max)

    IF @subjectLookupTableID IS NOT NULL AND @keyLookupTableID IS NOT NULL
    BEGIN
      -- Subject + Key, Single column
      IF @counterType != 'D'
        RAISERROR ('Counter is not valid, subject and key lookup set and counter not of type D', 16, 1)
      SET @sql = 'SELECT TOP (@pRows) C.subjectID, subjectText = ISNULL(S.fullText, S.lookupText), C.keyID, keyText = ISNULL(K.fullText, K.lookupText), '
      IF @toDate IS NULL
        SET @sql = @sql + 'C.value'
      ELSE
        SET @sql = @sql + 'value = SUM(C.value)'
      SET @sql = @sql + CHAR(13) + ' FROM ' + @counterTable + ' C'
      SET @sql = @sql + CHAR(13) + ' LEFT JOIN zsystem.lookupValues S ON S.lookupTableID = @pSubjectLookupTableID AND S.lookupID = C.subjectID'
      SET @sql = @sql + CHAR(13) + ' LEFT JOIN zsystem.lookupValues K ON K.lookupTableID = @pKeyLookupTableID AND K.lookupID = C.keyID'
      SET @sql = @sql + CHAR(13) + ' WHERE C.counterID = @pCounterID AND '
      IF @toDate IS NULL
        SET @sql = @sql + 'C.counterDate = @pFromDate'
      ELSE
        SET @sql = @sql + 'C.counterDate BETWEEN @pFromDate AND @pToDate'

      -- *** *** *** temporarily hard coding columnID = 0 *** *** ***
      IF @counterTable = 'zmetric.subjectKeyCounters'
        SET @sql = @sql + ' AND C.columnID = 0'

      IF @lookupText IS NOT NULL AND @lookupText != ''
        SET @sql = @sql + ' AND (ISNULL(S.fullText, S.lookupText) LIKE ''%'' + @pLookupText + ''%'' OR ISNULL(K.fullText, K.lookupText) LIKE ''%'' + @pLookupText + ''%'')'
      IF @toDate IS NOT NULL
        SET @sql = @sql + CHAR(13) + ' GROUP BY C.subjectID, ISNULL(S.fullText, S.lookupText), C.keyID, ISNULL(K.fullText, K.lookupText)'
      SET @sql = @sql + CHAR(13) + ' ORDER BY 5'
      IF @orderDesc = 1
        SET @sql = @sql + ' DESC'
      EXEC sp_executesql @sql,
                         N'@pRows int, @pCounterID smallint, @pSubjectLookupTableID int, @pKeyLookupTableID int, @pFromDate date, @pToDate date, @pLookupText nvarchar(1000)',
                         @rows, @counterID, @subjectLookupTableID, @keyLookupTableID, @fromDate, @toDate, @lookupText
    END
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.columns WHERE counterID = @counterID)
      BEGIN
        -- Multiple columns (Single value / Multiple key values)
        DECLARE @columnID tinyint, @columnName nvarchar(200), @orderBy nvarchar(200), @sql2 nvarchar(max) = '', @alias nvarchar(10)
        IF @keyLookupTableID IS NULL
          SET @sql = 'SELECT TOP 1 '
        ELSE
          SET @sql = 'SELECT TOP (@pRows) C.keyID, keyText = ISNULL(K.fullText, K.lookupText)'
         SET @sql2 = ' FROM ' + @counterTable + ' C'
        IF @keyLookupTableID IS NOT NULL
          SET @sql2 = @sql2 + CHAR(13) + '    LEFT JOIN zsystem.lookupValues K ON K.lookupTableID = @pKeyLookupTableID AND K.lookupID = C.keyID'
        DECLARE @cursor CURSOR
        SET @cursor = CURSOR LOCAL FAST_FORWARD
          FOR SELECT columnID, columnName FROM zmetric.columns WHERE counterID = @counterID ORDER BY [order], columnID
        OPEN @cursor
        FETCH NEXT FROM @cursor INTO @columnID, @columnName
        WHILE @@FETCH_STATUS = 0
        BEGIN
          IF @orderColumnID IS NULL SET @orderColumnID = @columnID
          IF @columnID = @orderColumnID SET @orderBy = @columnName
          SET @alias = 'C'
          IF @columnID != @orderColumnID
            SET @alias = @alias + CONVERT(nvarchar, @columnID)
          IF @sql != 'SELECT TOP 1 '
            SET @sql = @sql + ',' + CHAR(13) + '       '
          SET @sql = @sql + '[' + @columnName + '] = '
          IF @toDate IS NULL
            SET @sql = @sql + 'ISNULL(' + @alias + '.value, 0)'
          ELSE
            SET @sql = @sql + 'SUM(ISNULL(' + @alias + '.value, 0))'
          IF @columnID = @orderColumnID
            SET @orderBy = '[' + @columnName + ']'
          ELSE
          BEGIN
            SET @sql2 = @sql2 + CHAR(13) + '    LEFT JOIN ' + @counterTable + ' ' + @alias + ' ON ' + @alias + '.counterID = C.counterID'

            IF @counterTable IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters')
              SET @sql2 = @sql2 + ' AND ' + @alias + '.columnID = ' + CONVERT(nvarchar, @columnID)

            IF @counterTable IN ('zmetric.subjectKeyCounters', 'zmetric.dateCounters')
              SET @sql2 = @sql2 + ' AND ' + @alias + '.subjectID = ' + CONVERT(nvarchar, @columnID)

            SET @sql2 = @sql2 + ' AND ' + @alias + '.counterDate = C.counterDate AND ' + @alias + '.keyID = C.keyID'
          END
          FETCH NEXT FROM @cursor INTO @columnID, @columnName
        END
        CLOSE @cursor
        DEALLOCATE @cursor
        SET @sql = @sql + CHAR(13) + @sql2
        SET @sql = @sql + CHAR(13) + ' WHERE C.counterID = @pCounterID AND '
        IF @toDate IS NULL
          SET @sql = @sql + 'C.counterDate = @pFromDate AND'
        ELSE
          SET @sql = @sql + 'C.counterDate BETWEEN @pFromDate AND @pToDate AND'

        IF @counterTable IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters')
          SET @sql = @sql + ' C.columnID = ' + CONVERT(nvarchar, @orderColumnID)

        IF @counterTable IN ('zmetric.subjectKeyCounters', 'zmetric.dateCounters')
          SET @sql = @sql + ' C.subjectID = ' + CONVERT(nvarchar, @orderColumnID)

        IF @keyLookupTableID IS NOT NULL
        BEGIN
          IF @lookupText IS NOT NULL AND @lookupText != ''
            SET @sql = @sql + ' AND ISNULL(K.fullText, K.lookupText) LIKE ''%'' + @pLookupText + ''%'''
          IF @toDate IS NOT NULL
            SET @sql = @sql + CHAR(13) + ' GROUP BY C.keyID, ISNULL(K.fullText, K.lookupText)'
          SET @sql = @sql + CHAR(13) + ' ORDER BY ' + @orderBy
          IF @orderDesc = 1
            SET @sql = @sql + ' DESC'
        END
        SET @sql = @sql + CHAR(13) + 'OPTION (FORCE ORDER)'
        EXEC sp_executesql @sql,
                           N'@pRows int, @pCounterID smallint, @pKeyLookupTableID int, @pFromDate date, @pToDate date, @pLookupText nvarchar(1000)',
                           @rows, @counterID, @keyLookupTableID, @fromDate, @toDate, @lookupText
      END
      ELSE
      BEGIN
        -- Single column
        IF @keyLookupTableID IS NULL
        BEGIN
          -- Single value, Single column
          SET @sql = 'SELECT TOP 1 '
          IF @toDate IS NULL
            SET @sql = @sql + 'value'
          ELSE
            SET @sql = @sql + 'value = SUM(value)'
          SET @sql = @sql + ' FROM ' + @counterTable + ' WHERE counterID = @pCounterID AND '
          IF @toDate IS NULL
            SET @sql = @sql + 'counterDate = @pFromDate'
          ELSE
            SET @sql = @sql + 'counterDate BETWEEN @pFromDate AND @pToDate'
          EXEC sp_executesql @sql, N'@pCounterID smallint, @pFromDate date, @pToDate date', @counterID, @fromDate, @toDate
        END
        ELSE
        BEGIN
          -- Multiple key values, Single column (not using WHERE subjectID = 0 as its not in the index, trusting that its always 0)
          SET @sql = 'SELECT TOP (@pRows) C.keyID, keyText = ISNULL(K.fullText, K.lookupText), '
          IF @toDate IS NULL
            SET @sql = @sql + 'C.value'
          ELSE
            SET @sql = @sql + 'value = SUM(C.value)'
          SET @sql = @sql + CHAR(13) + '  FROM ' + @counterTable + ' C'
          SET @sql = @sql + CHAR(13) + '    LEFT JOIN zsystem.lookupValues K ON K.lookupTableID = @pKeyLookupTableID AND K.lookupID = C.keyID'
          SET @sql = @sql + CHAR(13) + ' WHERE C.counterID = @pCounterID AND '
          IF @toDate IS NULL
            SET @sql = @sql + 'C.counterDate = @pFromDate'
          ELSE
            SET @sql = @sql + 'C.counterDate BETWEEN @pFromDate AND @pToDate'
          IF @lookupText IS NOT NULL AND @lookupText != ''
            SET @sql = @sql + ' AND ISNULL(K.fullText, K.lookupText) LIKE ''%'' + @pLookupText + ''%'''
          IF @toDate IS NOT NULL
            SET @sql = @sql + CHAR(13) + ' GROUP BY C.keyID, ISNULL(K.fullText, K.lookupText)'
          SET @sql = @sql + CHAR(13) + ' ORDER BY 3'
          IF @orderDesc = 1
            SET @sql = @sql + ' DESC'
          EXEC sp_executesql @sql,
                             N'@pRows int, @pCounterID smallint, @pKeyLookupTableID int, @pFromDate date, @pToDate date, @pLookupText nvarchar(1000)',
                             @rows, @counterID, @keyLookupTableID, @fromDate, @toDate, @lookupText
        END
      END
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.Counters_ReportData'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zmetric.Counters_ReportData TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveIndexStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveIndexStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveIndexStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET ANSI_WARNINGS OFF
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveIndexStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
    BEGIN
      DELETE FROM zmetric.keyCounters WHERE counterID = 30007 AND counterDate = @counterDate
      DELETE FROM zmetric.keyCounters WHERE counterID = 30008 AND counterDate = @counterDate
    END
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30007 AND counterDate = @counterDate)
        RAISERROR ('Index stats data exists', 16, 1)
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30008 AND counterDate = @counterDate)
        RAISERROR ('Table stats data exists', 16, 1)
    END

    DECLARE @indexStats TABLE
    (
      tableName    nvarchar(450)  NOT NULL,
      indexName    nvarchar(450)  NOT NULL,
      [rows]       bigint         NOT NULL,
      total_kb     bigint         NOT NULL,
      used_kb      bigint         NOT NULL,
      data_kb      bigint         NOT NULL,
      user_seeks   bigint         NULL,
      user_scans   bigint         NULL,
      user_lookups bigint         NULL,
      user_updates bigint         NULL
    )
    INSERT INTO @indexStats (tableName, indexName, [rows], total_kb, used_kb, data_kb, user_seeks, user_scans, user_lookups, user_updates)
         SELECT S.name + '.' + T.name, ISNULL(I.name, 'HEAP'),
                SUM(P.row_count),
                SUM(P.reserved_page_count * 8), SUM(P.used_page_count * 8), SUM(P.in_row_data_page_count * 8),
                MAX(U.user_seeks), MAX(U.user_scans), MAX(U.user_lookups), MAX(U.user_updates)
           FROM sys.tables T
             INNER JOIN sys.schemas S ON S.[schema_id] = T.[schema_id]
             INNER JOIN sys.indexes I ON I.[object_id] = T.[object_id]
               INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
               LEFT JOIN sys.dm_db_index_usage_stats U ON U.database_id = DB_ID() AND U.[object_id] = I.[object_id] AND U.index_id = I.index_id
          WHERE T.is_ms_shipped != 1
          GROUP BY S.name, T.name, I.name
          ORDER BY S.name, T.name, I.name

    DECLARE @rows bigint, @total_kb bigint, @used_kb bigint, @data_kb bigint,
            @user_seeks bigint, @user_scans bigint, @user_lookups bigint, @user_updates bigint,
            @keyText nvarchar(450), @keyID int

    -- INDEX STATISTICS
    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT tableName + '.' + indexName, [rows], total_kb, used_kb, data_kb, user_seeks, user_scans, user_lookups, user_updates
            FROM @indexStats
           ORDER BY tableName, indexName
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    WHILE @@FETCH_STATUS = 0
    BEGIN
      EXEC zmetric.KeyCounters_InsertMulti 30007, 'D', @counterDate, 2000000005, NULL, @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates

      FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- TABLE STATISTICS
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT tableName, MAX([rows]), SUM(total_kb), SUM(used_kb), SUM(data_kb), MAX(user_seeks), MAX(user_scans), MAX(user_lookups), MAX(user_updates)
            FROM @indexStats
           GROUP BY tableName
           ORDER BY tableName
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    WHILE @@FETCH_STATUS = 0
    BEGIN
      EXEC zmetric.KeyCounters_InsertMulti 30008, 'D', @counterDate, 2000000006, NULL, @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates

      FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- MAIL
    DECLARE @recipients varchar(max)
    SET @recipients = zsystem.Settings_Value('zmetric', 'Recipients-IndexStats')
    IF @recipients != '' AND zsystem.Settings_Value('zsystem', 'Database') = DB_NAME()
    BEGIN
      DECLARE @subtractDate date
      SET @subtractDate = DATEADD(day, -1, @counterDate)

      -- SEND MAIL...
      DECLARE @subject nvarchar(255)
      SET @subject = HOST_NAME() + '.' + DB_NAME() + ': Index Statistics'

      DECLARE @body nvarchar(MAX)
      SET @body = 
        -- rows
          N'<h3><font color=blue>Top 30 rows</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">table</th><th>rows</th><th>total_MB</th><th>used_MB</th><th>data_MB</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C1.value, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C2.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C3.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C4.value / 1024, 1), ''
          FROM zmetric.keyCounters C1
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000006 AND L.lookupID = C1.keyID
            LEFT JOIN zmetric.keyCounters C2 ON C2.counterID = C1.counterID AND C2.counterDate = C1.counterDate AND C2.columnID = 2 AND C2.keyID = C1.keyID
            LEFT JOIN zmetric.keyCounters C3 ON C3.counterID = C1.counterID AND C3.counterDate = C1.counterDate AND C3.columnID = 3 AND C3.keyID = C1.keyID
            LEFT JOIN zmetric.keyCounters C4 ON C4.counterID = C1.counterID AND C4.counterDate = C1.counterDate AND C4.columnID = 4 AND C4.keyID = C1.keyID
         WHERE C1.counterID = 30008 AND C1.counterDate = @counterDate AND C1.columnID = 1
         ORDER BY C1.value DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- total_MB
        + N'<h3><font color=blue>Top 30 total_MB</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">table</th><th>total_MB</th><th>used_MB</th><th>data_MB</th><th>rows</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C2.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C3.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C4.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C1.value, 1), ''
          FROM zmetric.keyCounters C2
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000006 AND L.lookupID = C2.keyID
            LEFT JOIN zmetric.keyCounters C3 ON C3.counterID = C2.counterID AND C3.counterDate = C2.counterDate AND C3.columnID = 3 AND C3.keyID = C2.keyID
            LEFT JOIN zmetric.keyCounters C4 ON C4.counterID = C2.counterID AND C4.counterDate = C2.counterDate AND C4.columnID = 4 AND C4.keyID = C2.keyID
            LEFT JOIN zmetric.keyCounters C1 ON C1.counterID = C2.counterID AND C1.counterDate = C2.counterDate AND C1.columnID = 1 AND C1.keyID = C2.keyID
         WHERE C2.counterID = 30008 AND C2.counterDate = @counterDate AND C2.columnID = 2
         ORDER BY C2.value DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_seeks (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_seeks</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C5.value - ISNULL(C5B.value, 0), 1), ''
          FROM zmetric.keyCounters C5
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C5.keyID
            LEFT JOIN zmetric.keyCounters C5B ON C5B.counterID = C5.counterID AND C5B.counterDate = @subtractDate AND C5B.columnID = C5.columnID AND C5B.keyID = C5.keyID
         WHERE C5.counterID = 30007 AND C5.counterDate = @counterDate AND C5.columnID = 5
         ORDER BY (C5.value - ISNULL(C5B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_scans (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_scans</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C6.value - ISNULL(C6B.value, 0), 1), ''
          FROM zmetric.keyCounters C6
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C6.keyID
            LEFT JOIN zmetric.keyCounters C6B ON C6B.counterID = C6.counterID AND C6B.counterDate = @subtractDate AND C6B.columnID = C6.columnID AND C6B.keyID = C6.keyID
         WHERE C6.counterID = 30007 AND C6.counterDate = @counterDate AND C6.columnID = 6
         ORDER BY (C6.value - ISNULL(C6B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_lookups (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_lookups</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C7.value - ISNULL(C7B.value, 0), 1), ''
          FROM zmetric.keyCounters C7
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C7.keyID
            LEFT JOIN zmetric.keyCounters C7B ON C7B.counterID = C7.counterID AND C7B.counterDate = @subtractDate AND C7B.columnID = C7.columnID AND C7B.keyID = C7.keyID
         WHERE C7.counterID = 30007 AND C7.counterDate = @counterDate AND C7.columnID = 7
         ORDER BY (C7.value - ISNULL(C7B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_updates (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_updates</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C8.value - ISNULL(C8B.value, 0), 1), ''
          FROM zmetric.keyCounters C8
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C8.keyID
            LEFT JOIN zmetric.keyCounters C8B ON C8B.counterID = C8.counterID AND C8B.counterDate = @subtractDate AND C8B.columnID = C8.columnID AND C8B.keyID = C8.keyID
         WHERE C8.counterID = 30007 AND C8.counterDate = @counterDate AND C8.columnID = 8
         ORDER BY (C8.value - ISNULL(C8B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

      EXEC zsystem.SendMail @recipients, @subject, @body, 'HTML'
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveIndexStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SavePerfCountersTotal') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SavePerfCountersTotal
GO
CREATE PROCEDURE zmetric.KeyCounters_SavePerfCountersTotal
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SavePerfCountersTotal') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30027 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30027 AND counterDate = @counterDate)
        RAISERROR ('Performance counters total data exists', 16, 1)
    END

    -- PERFORMANCE COUNTERS TOTAL
    DECLARE @object_name nvarchar(200), @counter_name nvarchar(200), @cntr_value bigint, @keyID int, @keyText nvarchar(450)

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT REPLACE(RTRIM([object_name]), 'SQLServer:', ''),
                 CASE WHEN [object_name] = 'SQLServer:SQL Errors' THEN RTRIM(instance_name) ELSE RTRIM(counter_name) END,
                 cntr_value
            FROM sys.dm_os_performance_counters
           WHERE cntr_type = 272696576
             AND cntr_value != 0
             AND (    ([object_name] = 'SQLServer:Access Methods' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Buffer Manager' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:General Statistics' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Latches' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Access Methods' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:SQL Statistics' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Databases' AND instance_name = '_Total')
                   OR ([object_name] = 'SQLServer:Locks' AND instance_name = '_Total')
                   OR ([object_name] = 'SQLServer:SQL Errors' AND instance_name != '_Total')
                 )
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @keyText = @object_name + ' :: ' + @counter_name

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, @keyText

      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @cntr_value)

      FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- ADDING A FEW SYSTEM FUNCTIONS TO THE MIX
    -- Azure does not support @@PACK_RECEIVED, @@PACK_SENT, @@PACKET_ERRORS, @@TOTAL_READ, @@TOTAL_WRITE and @@TOTAL_ERRORS
    IF CONVERT(varchar(max), SERVERPROPERTY('edition')) NOT LIKE '%Azure%'
    BEGIN
      DECLARE @pack_received int, @pack_sent int, @packet_errors int, @total_read int, @total_write int, @total_errors int

      EXEC sp_executesql N'
        SELECT @pack_received = @@PACK_RECEIVED, @pack_sent = @@PACK_SENT, @packet_errors = @@PACKET_ERRORS,
               @total_read = @@TOTAL_READ, @total_write = @@TOTAL_WRITE, @total_errors = @@TOTAL_ERRORS',
        N'@pack_received int OUTPUT, @pack_sent int OUTPUT, @packet_errors int OUTPUT, @total_read int OUTPUT, @total_write int OUTPUT, @total_errors int OUTPUT',
        @pack_received OUTPUT, @pack_sent OUTPUT, @packet_errors OUTPUT, @total_read OUTPUT, @total_write OUTPUT, @total_errors OUTPUT

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@PACK_RECEIVED'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @pack_received)

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@PACK_SENT'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @pack_sent)

      IF @packet_errors != 0
      BEGIN
        EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@PACKET_ERRORS'
        INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @packet_errors)
      END

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@TOTAL_READ'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @total_read)

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@TOTAL_WRITE'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @total_write)

      IF @total_errors != 0
      BEGIN
        EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@TOTAL_ERRORS'
        INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @total_errors)
      END
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SavePerfCountersTotal'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0005, 'jorundur'
GO






-- ################################################################################################
-- # CORE.J.6                                                                                     #
-- ################################################################################################

EXEC zsystem.Versions_Start 'CORE.J', 0006, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.DuplicateData') IS NOT NULL
  DROP PROCEDURE zdm.DuplicateData
GO
CREATE PROCEDURE zdm.DuplicateData
  @tableName   nvarchar(256),
  @oldKeyID    bigint,
  @newKeyID    bigint = NULL OUTPUT,
  @keyColumn   nvarchar(128) = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @columns nvarchar(max) = '', @identityColumn nvarchar(128)

  DECLARE @columnName nvarchar(128), @isIdentity bit

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT name, is_identity FROM sys.columns WHERE [object_id] = OBJECT_ID(@tableName) ORDER BY column_id
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @columnName, @isIdentity
  WHILE @@FETCH_STATUS = 0
  BEGIN
    IF @isIdentity = 1
      SET @identityColumn = @columnName
    ELSE
    BEGIN
      IF @keyColumn IS NULL OR @columnName != @keyColumn
      BEGIN
        IF @columns = ''
          SET @columns = @columnName
        ELSE
          SET @columns += ', ' + @columnName
      END
    END

    FETCH NEXT FROM @cursor INTO @columnName, @isIdentity
  END
  CLOSE @cursor
  DEALLOCATE @cursor

  IF @identityColumn IS NULL
  BEGIN
    RAISERROR ('Identity column not found', 16, 1)
    RETURN -1
  END

  DECLARE @stmt nvarchar(max)
  SET @stmt = 'INSERT INTO ' + @tableName + ' ('
  IF @keyColumn IS NOT NULL
    SET @stmt += @keyColumn + ', '
  SET @stmt += @columns + ')' + CHAR(13)
            + '     SELECT '
  IF @keyColumn IS NOT NULL
    SET @stmt += CONVERT(nvarchar, @newKeyID) + ', '
  SET @stmt += @columns + CHAR(13)
            + '       FROM ' + @tableName + CHAR(13)
            + '      WHERE '
  SET @stmt += ISNULL(@keyColumn, @identityColumn)
  SET @stmt += ' = ' + CONVERT(nvarchar, @oldKeyID)
  IF @keyColumn IS NULL
    SET @stmt += ';' + CHAR(13) + 'SET @pNewKeyID = SCOPE_IDENTITY()'
  EXEC sp_executesql @stmt, N'@pNewKeyID int OUTPUT', @newKeyID OUTPUT
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF TYPE_ID('zutil.BigintTable') IS NULL
  CREATE TYPE zutil.BigintTable AS TABLE (number bigint NOT NULL)
GO
GRANT EXECUTE ON TYPE::zutil.BigintTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF TYPE_ID('zutil.IntTable') IS NULL
  CREATE TYPE zutil.IntTable AS TABLE (number int NOT NULL)
GO
GRANT EXECUTE ON TYPE::zutil.IntTable TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IpLocations_IpInt') IS NOT NULL
  DROP FUNCTION zutil.IpLocations_IpInt
GO
CREATE FUNCTION zutil.IpLocations_IpInt(@ip varchar(15))
RETURNS bigint
BEGIN
  -- Code based on ip2location.dbo.Dot2LongIP
  DECLARE @ipA bigint, @ipB int, @ipC int, @ipD Int
  SELECT @ipA = LEFT(@ip, PATINDEX('%.%', @ip) - 1)
  SELECT @ip = RIGHT(@ip, LEN(@ip) - LEN(@ipA) - 1)
  SELECT @ipB = LEFT(@ip, PATINDEX('%.%', @ip) - 1)
  SELECT @ip = RIGHT(@ip, LEN(@ip) - LEN(@ipB) - 1)
  SELECT @ipC = LEFT(@ip, PATINDEX('%.%', @ip) - 1)
  SELECT @ip = RIGHT(@ip, LEN(@ip) - LEN(@ipC) - 1)
  SELECT @ipD = @ip
  RETURN (@ipA * 256 * 256 * 256) + (@ipB * 256*256) + (@ipC * 256) + @ipD
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.ipLocations') IS NULL
BEGIN
  CREATE TABLE zutil.ipLocations
  (
    ipFrom        bigint                                      NOT NULL,
    ipTo          bigint                                      NOT NULL,
    countryID     smallint                                    NULL,
    countryCode   char(2)       COLLATE Latin1_General_CI_AI  NULL,
    countryName   varchar(100)  COLLATE Latin1_General_CI_AI  NULL,
    region        varchar(200)  COLLATE Latin1_General_CI_AI  NULL,
    city          varchar(200)  COLLATE Latin1_General_CI_AI  NULL,
    latitude      real                                        NULL,
    longitude     real                                        NULL,
    zipCode       varchar(50)   COLLATE Latin1_General_CI_AI  NULL,
    timeZone      varchar(50)   COLLATE Latin1_General_CI_AI  NULL,
    ispName       varchar(300)  COLLATE Latin1_General_CI_AI  NULL,
    domainName    varchar(200)  COLLATE Latin1_General_CI_AI  NULL,
    --
    CONSTRAINT ipLocations_PK PRIMARY KEY CLUSTERED (ipFrom, ipTo)
  )
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.ipLocations_SWITCH') IS NULL
BEGIN
  CREATE TABLE zutil.ipLocations_SWITCH
  (
    ipFrom        bigint                                      NOT NULL,
    ipTo          bigint                                      NOT NULL,
    countryID     smallint                                    NULL,
    countryCode   char(2)       COLLATE Latin1_General_CI_AI  NULL,
    countryName   varchar(100)  COLLATE Latin1_General_CI_AI  NULL,
    region        varchar(200)  COLLATE Latin1_General_CI_AI  NULL,
    city          varchar(200)  COLLATE Latin1_General_CI_AI  NULL,
    latitude      real                                        NULL,
    longitude     real                                        NULL,
    zipCode       varchar(50)   COLLATE Latin1_General_CI_AI  NULL,
    timeZone      varchar(50)   COLLATE Latin1_General_CI_AI  NULL,
    ispName       varchar(300)  COLLATE Latin1_General_CI_AI  NULL,
    domainName    varchar(200)  COLLATE Latin1_General_CI_AI  NULL,
    --
    CONSTRAINT ipLocations_SWITCH_PK PRIMARY KEY CLUSTERED (ipFrom, ipTo)
  )
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IpLocations_ID') IS NOT NULL
  DROP FUNCTION zutil.IpLocations_ID
GO
CREATE FUNCTION zutil.IpLocations_ID(@ip varchar(15))
RETURNS smallint
BEGIN
  -- Code based on ip2location.dbo.IP2LocationLookupCountry
  DECLARE @ipInt bigint = zutil.IpLocations_IpInt(@ip)
  DECLARE @countryID smallint
  SELECT TOP 1 @countryID = countryID FROM zutil.ipLocations WHERE ipFrom <= @ipInt ORDER BY ipFrom DESC
  RETURN @countryID
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IpLocations_Code') IS NOT NULL
  DROP FUNCTION zutil.IpLocations_Code
GO
CREATE FUNCTION zutil.IpLocations_Code(@ip varchar(15))
RETURNS char(2)
BEGIN
  -- Code based on ip2location.dbo.IP2LocationLookupCountry
  DECLARE @ipInt bigint = zutil.IpLocations_IpInt(@ip)
  DECLARE @countryCode char(2)
  SELECT TOP 1 @countryCode = countryCode FROM zutil.ipLocations WHERE ipFrom <= @ipInt ORDER BY ipFrom DESC
  RETURN @countryCode
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IpLocations_Select') IS NOT NULL
  DROP PROCEDURE zutil.IpLocations_Select
GO
CREATE PROCEDURE zutil.IpLocations_Select
  @ip  varchar(15)
AS
  -- Code based on ip2location.dbo.IP2LocationLookupCountry
  SET NOCOUNT ON

  DECLARE @ipInt bigint = zutil.IpLocations_IpInt(@ip)
  SELECT TOP 1 countryID, countryCode, countryName, region, city, latitude, longitude, zipCode, timeZone, ispName, domainName
    FROM zutil.ipLocations
   WHERE ipFrom <= @ipInt
   ORDER BY ipFrom DESC
GO
GRANT EXEC ON zutil.IpLocations_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.IpLocations_SelectList') IS NOT NULL
  DROP PROCEDURE zutil.IpLocations_SelectList
GO
CREATE PROCEDURE zutil.IpLocations_SelectList
  @ips  varchar(max)
AS
  -- Code based on ip2location.dbo.IP2LocationLookupCountry
  SET NOCOUNT ON

  DECLARE @table TABLE
  (
    ipInt        bigint       PRIMARY KEY,
    ip           varchar(15),
    countryID    smallint,
    countryCode  char(2),
    countryName  varchar(100),
    region       varchar(200),
    city         varchar(200),
    latitude     real,
    longitude    real,
    zipCode      varchar(50),
    timeZone     varchar(50),
    ispName      varchar(300),
    domainName   varchar(200)
  )

  INSERT INTO @table (ipInt, ip)
       SELECT zutil.IpLocations_IpInt(string), string FROM zutil.CharListToTable(@ips)

  DECLARE @ipInt bigint,
          @countryID smallint, @countryCode char(2), @countryName varchar(100), @region varchar(200), @city varchar(200),
          @latitude real, @longitude real, @zipCode varchar(50), @timeZone varchar(50), @ispName varchar(300), @domainName varchar(200)

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT ipInt FROM @table
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @ipInt
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SELECT @countryID = NULL, @countryCode = NULL, @countryName = NULL, @region = NULL, @city = NULL,
           @latitude = NULL, @longitude = NULL, @zipCode = NULL, @timeZone = NULL, @ispName = NULL, @domainName = NULL

    SELECT TOP 1 @countryID = countryID, @countryCode = countryCode, @countryName = countryName, @region = region, @city = city,
           @latitude = latitude, @longitude = longitude, @zipCode = zipCode, @timeZone = timeZone, @ispName = ispName, @domainName = domainName
      FROM zutil.ipLocations
     WHERE ipFrom <= @ipInt
     ORDER BY ipFrom DESC

    UPDATE @table
       SET countryID = @countryID, countryCode = @countryCode, countryName = @countryName, region = @region, city = @city,
           latitude = @latitude, longitude = @longitude, zipCode = @zipCode, timeZone = @timeZone, ispName = @ispName, domainName = @domainName
     WHERE ipInt = @ipInt

    FETCH NEXT FROM @cursor INTO @ipInt
  END
  CLOSE @cursor
  DEALLOCATE @cursor

  SELECT ip, countryID, countryCode, countryName, region, city, latitude, longitude, zipCode, timeZone, ispName, domainName
    FROM @table
GO
GRANT EXEC ON zutil.IpLocations_SelectList TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0006, 'jorundur'
GO






-- ################################################################################################
-- # CORE.J.7                                                                                     #
-- ################################################################################################

EXEC zsystem.Versions_Start 'CORE.J', 0007, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.TimeStringSeconds') IS NOT NULL
  DROP FUNCTION zutil.TimeStringSeconds
GO
CREATE FUNCTION zutil.TimeStringSeconds(@timeString varchar(20))
RETURNS int
BEGIN
  DECLARE @seconds int, @minutesSeconds char(5), @hours varchar(14)

  SET @minutesSeconds = RIGHT(@timeString, 5)
  SET @hours = LEFT(@timeString, LEN(@timeString) - 6)

  SET @seconds = CONVERT(int, RIGHT(@minutesSeconds, 2))
  SET @seconds = @seconds + (CONVERT(int, LEFT(@minutesSeconds, 2) * 60))
  SET @seconds = @seconds + (CONVERT(int, @hours * 3600))

  RETURN @seconds
END
GO
GRANT EXEC ON zutil.TimeStringSeconds TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.mountpoints') IS NOT NULL
  DROP PROCEDURE zdm.mountpoints
GO
CREATE PROCEDURE zdm.mountpoints
  @filter  nvarchar(300) = ''
AS
  SET NOCOUNT ON

  EXEC zdm.info 'mountpoints', @filter
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.topsql') IS NOT NULL
  DROP PROCEDURE zdm.topsql
GO
CREATE PROCEDURE zdm.topsql
  @rows  smallint = 30
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @now datetime2(0) = GETDATE()

  IF NOT EXISTS(SELECT 1 FROM sys.dm_exec_requests WHERE blocking_session_id != 0)
  BEGIN
    -- No blocking, light version
    SELECT TOP (@rows) start_time = CONVERT(datetime2(0), R.start_time), run_time = zutil.TimeString(ABS(DATEDIFF(second, R.start_time, @now))),
           R.session_id, blocking_id = R.blocking_session_id, R.logical_reads,
           S.[host_name], S.[program_name], S.login_name, database_name = DB_NAME(R.database_id),
           [object_name] = OBJECT_SCHEMA_NAME(T.objectid, R.database_id) + '.' + OBJECT_NAME(T.objectid, R.database_id),
           T.[text], R.command, R.[status], estimated_completion_time = zutil.TimeString(R.estimated_completion_time / 1000),
           wait_time = zutil.TimeString(R.wait_time / 1000), R.last_wait_type, cpu_time = zutil.TimeString(R.cpu_time / 1000),
           total_elapsed_time = zutil.TimeString(R.total_elapsed_time / 1000), R.reads, R.writes,
           R.open_transaction_count, R.open_resultset_count, R.percent_complete, R.database_id,
           [object_id] = T.objectid, S.host_process_id, S.client_interface_name, R.[sql_handle], R.plan_handle
      FROM sys.dm_exec_requests R
        CROSS APPLY sys.dm_exec_sql_text(R.[sql_handle]) T
        LEFT JOIN sys.dm_exec_sessions S ON S.session_id = R.session_id
     ORDER BY R.start_time
  END
  ELSE
  BEGIN
    -- Blocking, add blocking info rowset
    DECLARE @topsql TABLE
    (
      start_time                 datetime2(0),
      run_time                   varchar(20),
      session_id                 smallint,
      blocking_id                smallint,
      logical_reads              bigint,
      [host_name]                nvarchar(128),
      [program_name]             nvarchar(128),
      login_name                 nvarchar(128),
      database_name              nvarchar(128),
      [object_name]              nvarchar(256),
      [text]                     nvarchar(max),
      command                    nvarchar(32),
      [status]                   nvarchar(30),
      estimated_completion_time  varchar(20),
      wait_time                  varchar(20),
      last_wait_type             nvarchar(60),
      cpu_time                   varchar(20),
      total_elapsed_time         varchar(20),
      reads                      bigint,
      writes                     bigint,
      open_transaction_count     int,
      open_resultset_count       int,
      percent_complete           real,
      database_id                smallint,
      [object_id]                int,
      host_process_id            int,
      client_interface_name      nvarchar(32),
      [sql_handle]               varbinary(64),
      plan_handle                varbinary(64)
    )

    INSERT INTO @topsql
         SELECT TOP (@rows) start_time = CONVERT(datetime2(0), R.start_time), run_time = zutil.TimeString(ABS(DATEDIFF(second, R.start_time, @now))),
                R.session_id, blocking_id = R.blocking_session_id, R.logical_reads,
                S.[host_name], S.[program_name], S.login_name, database_name = DB_NAME(R.database_id),
                [object_name] = OBJECT_SCHEMA_NAME(T.objectid, R.database_id) + '.' + OBJECT_NAME(T.objectid, R.database_id),
                T.[text], R.command, R.[status], estimated_completion_time = zutil.TimeString(R.estimated_completion_time / 1000),
                wait_time = zutil.TimeString(R.wait_time / 1000), R.last_wait_type, cpu_time = zutil.TimeString(R.cpu_time / 1000),
                total_elapsed_time = zutil.TimeString(R.total_elapsed_time / 1000), R.reads, R.writes,
                R.open_transaction_count, R.open_resultset_count, R.percent_complete, R.database_id,
                [object_id] = T.objectid, S.host_process_id, S.client_interface_name, R.[sql_handle], R.plan_handle
           FROM sys.dm_exec_requests R
             CROSS APPLY sys.dm_exec_sql_text(R.[sql_handle]) T
             LEFT JOIN sys.dm_exec_sessions S ON S.session_id = R.session_id

    SELECT 'Blocking info' AS Info, start_time, run_time, session_id, blocking_id, logical_reads,
            [host_name], [program_name], login_name, database_name, [object_name],
            [text], command, [status], estimated_completion_time, wait_time, last_wait_type, cpu_time,
            total_elapsed_time, reads, writes,
            open_transaction_count, open_resultset_count, percent_complete, database_id,
            [object_id], host_process_id, client_interface_name, [sql_handle], plan_handle
      FROM @topsql
      WHERE blocking_id IN (select session_id FROM @topsql) OR session_id IN (select blocking_id FROM @topsql)
      ORDER BY blocking_id, session_id

    SELECT start_time, run_time, session_id, blocking_id, logical_reads,
           [host_name], [program_name], login_name, database_name, [object_name],
           [text], command, [status], estimated_completion_time, wait_time, last_wait_type, cpu_time,
           total_elapsed_time, reads, writes,
           open_transaction_count, open_resultset_count, percent_complete, database_id,
           [object_id], host_process_id, client_interface_name, [sql_handle], plan_handle
      FROM @topsql
     ORDER BY start_time
  END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zdm.t') IS NOT NULL
  DROP SYNONYM zdm.t
GO
CREATE SYNONYM zdm.t FOR zdm.topsql
GO



IF OBJECT_ID('zdm.topsqlp') IS NOT NULL
  DROP PROCEDURE zdm.topsqlp
GO
CREATE PROCEDURE zdm.topsqlp
  @rows  smallint = 30
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @now datetime2(0) = GETDATE()

  IF NOT EXISTS(SELECT 1 FROM sys.dm_exec_requests WHERE blocking_session_id != 0)
  BEGIN
    -- No blocking, light version
    SELECT TOP (@rows) P.query_plan, start_time = CONVERT(datetime2(0), R.start_time), run_time = zutil.TimeString(ABS(DATEDIFF(second, R.start_time, @now))),
           R.session_id, blocking_id = R.blocking_session_id, R.logical_reads,
           S.[host_name], S.[program_name], S.login_name, database_name = DB_NAME(R.database_id),
           [object_name] = OBJECT_SCHEMA_NAME(T.objectid, R.database_id) + '.' + OBJECT_NAME(T.objectid, R.database_id),
           T.[text], R.command, R.[status], estimated_completion_time = zutil.TimeString(R.estimated_completion_time / 1000),
           wait_time = zutil.TimeString(R.wait_time / 1000), R.last_wait_type, cpu_time = zutil.TimeString(R.cpu_time / 1000),
           total_elapsed_time = zutil.TimeString(R.total_elapsed_time / 1000), R.reads, R.writes,
           R.open_transaction_count, R.open_resultset_count, R.percent_complete, R.database_id,
           [object_id] = T.objectid, S.host_process_id, S.client_interface_name, R.[sql_handle], R.plan_handle
      FROM sys.dm_exec_requests R
        CROSS APPLY sys.dm_exec_sql_text(R.[sql_handle]) T
        CROSS APPLY sys.dm_exec_query_plan(R.plan_handle) P
        LEFT JOIN sys.dm_exec_sessions S ON S.session_id = R.session_id
     ORDER BY R.start_time
  END
  ELSE
  BEGIN
    -- Blocking, add blocking info rowset
    DECLARE @topsql TABLE
    (
      query_plan                 xml,
      start_time                 datetime2(0),
      run_time                   varchar(20),
      session_id                 smallint,
      blocking_id                smallint,
      logical_reads              bigint,
      [host_name]                nvarchar(128),
      [program_name]             nvarchar(128),
      login_name                 nvarchar(128),
      database_name              nvarchar(128),
      [object_name]              nvarchar(256),
      [text]                     nvarchar(max),
      command                    nvarchar(32),
      [status]                   nvarchar(30),
      estimated_completion_time  varchar(20),
      wait_time                  varchar(20),
      last_wait_type             nvarchar(60),
      cpu_time                   varchar(20),
      total_elapsed_time         varchar(20),
      reads                      bigint,
      writes                     bigint,
      open_transaction_count     int,
      open_resultset_count       int,
      percent_complete           real,
      database_id                smallint,
      [object_id]                int,
      host_process_id            int,
      client_interface_name      nvarchar(32),
      [sql_handle]               varbinary(64),
      plan_handle                varbinary(64)
    )

    INSERT INTO @topsql
         SELECT TOP (@rows) P.query_plan, start_time = CONVERT(datetime2(0), R.start_time), run_time = zutil.TimeString(ABS(DATEDIFF(second, R.start_time, @now))),
                R.session_id, blocking_id = R.blocking_session_id, R.logical_reads,
                S.[host_name], S.[program_name], S.login_name, database_name = DB_NAME(R.database_id),
                [object_name] = OBJECT_SCHEMA_NAME(T.objectid, R.database_id) + '.' + OBJECT_NAME(T.objectid, R.database_id),
                T.[text], R.command, R.[status], estimated_completion_time = zutil.TimeString(R.estimated_completion_time / 1000),
                wait_time = zutil.TimeString(R.wait_time / 1000), R.last_wait_type, cpu_time = zutil.TimeString(R.cpu_time / 1000),
                total_elapsed_time = zutil.TimeString(R.total_elapsed_time / 1000), R.reads, R.writes,
                R.open_transaction_count, R.open_resultset_count, R.percent_complete, R.database_id,
                [object_id] = T.objectid, S.host_process_id, S.client_interface_name, R.[sql_handle], R.plan_handle
           FROM sys.dm_exec_requests R
             CROSS APPLY sys.dm_exec_sql_text(R.[sql_handle]) T
             CROSS APPLY sys.dm_exec_query_plan(R.plan_handle) P
             LEFT JOIN sys.dm_exec_sessions S ON S.session_id = R.session_id

    SELECT 'Blocking info' AS Info, query_plan, start_time, run_time, session_id, blocking_id, logical_reads,
            [host_name], [program_name], login_name, database_name, [object_name],
            [text], command, [status], estimated_completion_time, wait_time, last_wait_type, cpu_time,
            total_elapsed_time, reads, writes,
            open_transaction_count, open_resultset_count, percent_complete, database_id,
            [object_id], host_process_id, client_interface_name, [sql_handle], plan_handle
      FROM @topsql
      WHERE blocking_id IN (select session_id FROM @topsql) OR session_id IN (select blocking_id FROM @topsql)
      ORDER BY blocking_id, session_id

    SELECT query_plan, start_time, run_time, session_id, blocking_id, logical_reads,
           [host_name], [program_name], login_name, database_name, [object_name],
           [text], command, [status], estimated_completion_time, wait_time, last_wait_type, cpu_time,
           total_elapsed_time, reads, writes,
           open_transaction_count, open_resultset_count, percent_complete, database_id,
           [object_id], host_process_id, client_interface_name, [sql_handle], plan_handle
      FROM @topsql
     ORDER BY start_time
  END
GO


IF OBJECT_ID('zdm.tp') IS NOT NULL
  DROP SYNONYM zdm.tp
GO
CREATE SYNONYM zdm.tp FOR zdm.topsqlp
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.MinInt') IS NOT NULL
  DROP FUNCTION zutil.MinInt
GO
CREATE FUNCTION zutil.MinInt(@value1 int, @value2 int)
RETURNS int
BEGIN
  DECLARE @i int
  IF @value1 < @value2
    SET @i = @value1
  ELSE
    SET @i = @value2
  RETURN @i
END
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.MinFloat') IS NOT NULL
  DROP FUNCTION zutil.MinFloat
GO
CREATE FUNCTION zutil.MinFloat(@value1 float, @value2 float)
RETURNS float
BEGIN
  DECLARE @f float
  IF @value1 < @value2
    SET @f = @value1
  ELSE
    SET @f = @value2
  RETURN @f
END
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'EventsFilter')
  INSERT INTO zsystem.settings ([group], [key], [value], [description], defaultValue)
       VALUES ('zsystem', 'EventsFilter', '', 'Filter to use when listing zsystem.events using zsystem.Events_Select.  Note that the function system.Events_AppFilter needs to be added to implement the filter.', '')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_Select') IS NOT NULL
  DROP PROCEDURE zsystem.Events_Select
GO
CREATE PROCEDURE zsystem.Events_Select
  @filter   varchar(50) = '',
  @rows     smallint = 1000,
  @eventID  int = NULL,
  @text     nvarchar(450) = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF @eventID IS NULL SET @eventID = 2147483647

  DECLARE @stmt nvarchar(max)

  SET @stmt = 'SELECT TOP (@pRows) * FROM zsystem.eventsEx WHERE eventID < @pEventID'


  -- Application Hook!
  IF @filter != '' AND OBJECT_ID('system.Events_AppFilter') IS NOT NULL
  BEGIN
    DECLARE @where nvarchar(max)
    EXEC sp_executesql N'SELECT @p_where = system.Events_AppFilter(@p_filter)', N'@p_where nvarchar(max) OUTPUT, @p_filter varchar(50)', @where OUTPUT, @filter
    SET @stmt += @where
  END

  IF @text IS NOT NULL
  BEGIN
    SET @text = '%' + LOWER(@text) + '%'
    SET @stmt += ' AND (LOWER(eventTypeName) LIKE @pText OR taskName LIKE @pText OR fixedText LIKE @pText OR LOWER(eventText) LIKE @pText)'
  END

  SET @stmt += ' ORDER BY eventID DESC'

  EXEC sp_executesql @stmt, N'@pRows smallint, @pEventID int, @pText nvarchar(450)', @pRows = @rows, @pEventID = @eventID, @pText = @text
GO
GRANT EXEC ON zsystem.Events_Select TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Events_SelectByEvent') IS NOT NULL
  DROP PROCEDURE zsystem.Events_SelectByEvent
GO
CREATE PROCEDURE zsystem.Events_SelectByEvent
  @eventID  int
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    DECLARE @eventDate datetime2(0), @parentID int
    SELECT @eventDate = eventDate, @parentID = parentID FROM zsystem.events WHERE eventID = @eventID
    IF @eventDate IS NULL
      RAISERROR ('Event not found', 16, 1)

    -- Setting from/to interval to 3 days, 1 day before and 1 day after
    DECLARE @fromID int, @toID int
    SET @fromID = zsystem.Identities_Int(2000100014, @eventDate, -1, 0)
    IF @fromID < 0
      RAISERROR ('Identity not found', 16, 1)
    SET @toID = zsystem.Identities_Int(2000100014, @eventDate, 2, 0) - 1
    IF @toID < 0 SET @toID = 2147483647

    -- Table for events returned
    DECLARE @events TABLE (eventID int NOT NULL PRIMARY KEY, eventLevel int NULL)

    -- Find top level parent event
    IF @parentID IS NOT NULL
    BEGIN
      DECLARE @nextParentID int = 0, @c tinyint = 0, @masterID int
      WHILE 1 = 1
      BEGIN
        SET @nextParentID = NULL
        SELECT @nextParentID = parentID FROM zsystem.events WHERE eventID = @parentID
        IF @nextParentID IS NULL
        BEGIN
          SET @masterID = @parentID
          BREAK
        END
        SET @parentID = @nextParentID
        SET @c += 1
        IF @c > 30
        BEGIN
          RAISERROR ('Recursion > 30 in search for master eventID', 16, 1)
          RETURN -1
        END
      END
      SET @eventID = @masterID
    END

    -- Initialize @events table with top level event(s)
    DECLARE @eventTypeID int, @referenceID int, @duration int
    DECLARE @startedEventID int, @completedEventID int
    SELECT @eventTypeID = eventTypeID, @referenceID = referenceID, @duration = duration FROM zsystem.events WHERE eventID = @eventID
    IF @eventTypeID IS NULL
      RAISERROR ('Event not found', 16, 1)
    IF @eventTypeID NOT BETWEEN 2000001001 AND 2000001004 -- Task started/info/completed/ERROR
    BEGIN
      -- Not a task event, simple initialize
      INSERT INTO @events (eventID, eventLevel) VALUES (@eventID, 1)
      SET @startedEventID = @eventID
      SET @completedEventID = @toID
    END
    ELSE
    BEGIN
      -- Find started and completed events
      IF @eventTypeID = 2000001001 -- Task started
      BEGIN
        SET @startedEventID = @eventID
        SET @referenceID = @eventID
      END
      ELSE
      BEGIN
        IF ISNULL(@referenceID, 0) > 0
          SET @startedEventID = @referenceID
        ELSE
        BEGIN
          SET @startedEventID = @eventID
          SET @referenceID = @eventID
        END
      END
      IF @eventTypeID = 2000001003 OR (@eventTypeID = 2000001004 AND @duration IS NOT NULL) -- Task completed / Task ERROR with duration set
        SET @completedEventID = @eventID
      ELSE
      BEGIN
        -- Find the completed event
        SELECT TOP 1 @completedEventID = eventID
          FROM zsystem.events
          WHERE eventID BETWEEN @eventID AND @toID
            AND (eventTypeID = 2000001003 OR (eventTypeID = 2000001004 AND duration IS NOT NULL)) AND referenceID = @referenceID
          ORDER BY eventID

        IF @completedEventID IS NULL
          SET @completedEventID = @toID
      END
      INSERT INTO @events (eventID, eventLevel)
           SELECT eventID, 1
             FROM zsystem.events
            WHERE eventID BETWEEN @startedEventID AND @completedEventID AND (eventID = @referenceID OR referenceID = @referenceID)
    END

    -- Recursively add child events
    DECLARE @eventLevel int = 1
    WHILE @eventLevel < 20
    BEGIN
      INSERT INTO @events (eventID, eventLevel)
           SELECT eventID, @eventLevel + 1
             FROM zsystem.events
            WHERE eventID BETWEEN @startedEventID AND @completedEventID AND parentID IN (SELECT eventID FROM @events WHERE eventLevel = @eventLevel)
      IF @@ROWCOUNT = 0
        BREAK
      SET @eventLevel += 1
    END

    -- Return all top level and child events
    SELECT X.eventLevel, E.*
      FROM @events X
        INNER JOIN zsystem.eventsEx E ON E.eventID = X.eventID
     ORDER BY E.eventID DESC
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zsystem.Events_SelectByEvent'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zsystem.Events_SelectByEvent TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Settings_Update') IS NOT NULL
  DROP PROCEDURE zsystem.Settings_Update
GO
CREATE PROCEDURE zsystem.Settings_Update
  @group              varchar(200), 
  @key                varchar(200), 
  @value              nvarchar(max),
  @userID             int = NULL,
  @insertIfNotExists  bit = 0
AS
  SET NOCOUNT ON

  BEGIN TRY
    DECLARE @allowUpdate bit
    SELECT @allowUpdate = allowUpdate FROM zsystem.settings WHERE [group] = @group AND [key] = @key
    IF @allowUpdate IS NULL AND @insertIfNotExists = 0
      RAISERROR ('Setting not found', 16, 1)
    IF @allowUpdate = 0 AND @insertIfNotExists = 0
      RAISERROR ('Update not allowed', 16, 1)

    DECLARE @fixedText nvarchar(450) = @group + '.' + @key

    BEGIN TRANSACTION

    IF @allowUpdate IS NULL AND @insertIfNotExists = 1
    BEGIN
      INSERT INTO zsystem.settings ([group], [key], value, [description]) VALUES (@group, @key, @value, '')

      EXEC zsystem.Events_Insert 2000000032, NULL, @userID, @fixedText=@fixedText, @eventText=@value
    END
    ELSE
    BEGIN
      UPDATE zsystem.settings
          SET value = @value
        WHERE [group] = @group AND [key] = @key AND [value] != @value
      IF @@ROWCOUNT > 0
        EXEC zsystem.Events_Insert 2000000031, NULL, @userID, @fixedText=@fixedText, @eventText=@value
    END

    COMMIT TRANSACTION
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0
      ROLLBACK TRANSACTION
    EXEC zsystem.CatchError 'zsystem.Settings_Update'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM sys.columns WHERE [object_id] = OBJECT_ID('zmetric.counters') AND [name] = 'autoDeleteMaxDays')
  ALTER TABLE zmetric.counters ADD autoDeleteMaxDays smallint NULL
GO


---------------------------------------------------------------------------------------------------------------------------------


UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30007 AND autoDeleteMaxDays IS NULL
UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30008 AND autoDeleteMaxDays IS NULL
UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30009 AND autoDeleteMaxDays IS NULL
UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30025 AND autoDeleteMaxDays IS NULL
UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30026 AND autoDeleteMaxDays IS NULL
UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30027 AND autoDeleteMaxDays IS NULL
UPDATE zmetric.counters SET autoDeleteMaxDays = 500 WHERE counterID = 30028 AND autoDeleteMaxDays IS NULL
GO


---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'AutoDeleteMaxRows')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'AutoDeleteMaxRows', '50000', '50000', 'Max rows to delete when zmetric.counters.autoDeleteMaxDays (set to "0" to disable).  See proc zmetric.Counters_SaveStats.')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_SaveStats') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_SaveStats
GO
CREATE PROCEDURE zmetric.Counters_SaveStats
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC zmetric.KeyCounters_SaveIndexStats
  EXEC zmetric.KeyCounters_SaveProcStats
  EXEC zmetric.KeyCounters_SaveFileStats
  EXEC zmetric.KeyCounters_SaveWaitStats
  EXEC zmetric.KeyCounters_SavePerfCountersTotal
  EXEC zmetric.KeyCounters_SavePerfCountersInstance

  --
  -- Auto delete old data
  --
  DECLARE @autoDeleteMaxRows int = zsystem.Settings_Value('zmetric', 'AutoDeleteMaxRows')
  IF @autoDeleteMaxRows < 1
    RETURN

  DECLARE @counterDate date, @counterDateTime datetime2(0)

  DECLARE @counterID smallint, @counterTable nvarchar(256), @autoDeleteMaxDays smallint

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT counterID, counterTable, autoDeleteMaxDays FROM zmetric.counters WHERE autoDeleteMaxDays > 0 ORDER BY counterID
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @counterID, @counterTable, @autoDeleteMaxDays
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @counterDate = DATEADD(day, -@autoDeleteMaxDays, GETDATE())
    SET @counterDateTime = @counterDate

    IF @counterTable = 'zmetric.keyCounters'
    BEGIN
      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate < @counterDate
      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.keyTimeCounters WHERE counterID = @counterID AND counterDate < @counterDateTime
    END
    ELSE IF @counterTable = 'zmetric.subjectKeyCounters'
      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate < @counterDate
    ELSE IF @counterTable = 'zmetric.simpleCounters'
      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.simpleCounters WHERE counterID = @counterID AND counterDate < @counterDateTime

    FETCH NEXT FROM @cursor INTO @counterID, @counterTable, @autoDeleteMaxDays
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------------------------------------



EXEC zsystem.Versions_Finish 'CORE.J', 0007, 'jorundur'
GO
