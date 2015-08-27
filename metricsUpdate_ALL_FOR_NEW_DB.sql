
USE ebs_METRICS
GO



--
-- zmetric   ALTER + DEPRECATED STUFF!
--

EXEC zdm.DropDefaultConstraint 'zmetric.counters', 'createDate'
ALTER TABLE zmetric.counters ALTER COLUMN createDate datetime NOT NULL
ALTER TABLE zmetric.counters ADD DEFAULT GETUTCDATE() FOR createDate
GO

EXEC zdm.DropDefaultConstraint 'zmetric.counters', 'modifyDate'
ALTER TABLE zmetric.counters ALTER COLUMN modifyDate datetime NOT NULL
ALTER TABLE zmetric.counters ADD DEFAULT GETUTCDATE() FOR modifyDate
GO


ALTER TABLE zmetric.keyTimeCounters DROP CONSTRAINT keyTimeCounters_PK
ALTER TABLE zmetric.keyTimeCounters ALTER COLUMN counterDate datetime NOT NULL
ALTER TABLE zmetric.keyTimeCounters ADD CONSTRAINT keyTimeCounters_PK PRIMARY KEY CLUSTERED (counterID, columnID, keyID, counterDate)
GO



-- This table is deprecated, it will be dropped once EVE Metrics has been changed to use zmetric.keyCounters and zmetric.subjectKeyCounters

IF OBJECT_ID('zmetric.dateCounters') IS NULL
BEGIN
  CREATE TABLE zmetric.dateCounters
  (
    counterID    smallint  NOT NULL,  -- Counter, poining to zmetric.counters
    counterDate  date      NOT NULL,  -- Date
    subjectID    int       NOT NULL,  -- Subject if used, f.e. if counting for user or character, 0 if not used
    keyID        int       NOT NULL,  -- Key if used, f.e. if counting kills for character per solar system, 0 if not used
    value        float     NOT NULL,  -- Value
    --
    CONSTRAINT dateCounters_PK PRIMARY KEY CLUSTERED (counterID, subjectID, keyID, counterDate)
  )

  CREATE NONCLUSTERED INDEX dateCounters_IX_CounterDate ON zmetric.dateCounters (counterID, counterDate, value)
END
GRANT SELECT ON zmetric.dateCounters TO zzp_server
GO



IF OBJECT_ID('zmetric.dateCountersEx') IS NOT NULL
  DROP VIEW zmetric.dateCountersEx
GO
CREATE VIEW zmetric.dateCountersEx
AS
  SELECT C.groupID, G.groupName, DC.counterID, C.counterName, DC.counterDate,
         DC.subjectID, subjectText = COALESCE(O.columnName, LS.[fullText], LS.lookupText),
         DC.keyID, keyText = ISNULL(LK.[fullText], LK.lookupText), DC.[value]
    FROM zmetric.dateCounters DC
      LEFT JOIN zmetric.counters C ON C.counterID = DC.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
        LEFT JOIN zsystem.lookupValues LS ON LS.lookupTableID = C.subjectLookupTableID AND LS.lookupID = DC.subjectID
        LEFT JOIN zsystem.lookupValues LK ON LK.lookupTableID = C.keyLookupTableID AND LK.lookupID = DC.keyID
      LEFT JOIN zmetric.columns O ON O.counterID = DC.counterID AND CONVERT(int, O.columnID) = DC.subjectID
GO
GRANT SELECT ON zmetric.dateCountersEx TO zzp_server
GO



--
-- zmetric   CHANGING zmetric.Counters_Insert TO ADD COUNTERS WITH counterTable=zmetric.keyCounters AND counterType=C if @counterTable IS NULL
--

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

  IF @counterTable IS NULL SELECT @counterTable = 'zmetric.keyCounters', @counterType = 'C' -- *** *** ***

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



--
-- Get rid of None group on Reports page
--

update zmetric.counters set hidden = 1 where counterID > 30000
go



--
-- data
--

IF SCHEMA_ID('data') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA data'
GO



--
-- dbo
--

IF OBJECT_ID('dbo.tags') IS NULL
BEGIN
  CREATE TABLE dbo.tags
  (
    tagID           int            NOT NULL  IDENTITY(1, 1),
    tagName         nvarchar(100)  NOT NULL,
    --
    CONSTRAINT tags_PK PRIMARY KEY CLUSTERED (tagID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX [tags_UQ_Name] ON [dbo].[tags] ([tagName] ASC)
END
GO


--drop table dbo.tagLinks
IF OBJECT_ID('dbo.tagLinks') IS NULL
BEGIN
  CREATE TABLE dbo.tagLinks
  (
	  [tagLinkID]  [int] IDENTITY(1,1) NOT NULL,
	  [linkType]   [tinyint] NOT NULL,
	  [linkID]     [int] NOT NULL,
	  [tagID]      [int] NOT NULL,
	  [userID]     [int] NULL,
	  [dateTime]   [smalldatetime] NULL CONSTRAINT [DF_tagLinks2_dateTime]  DEFAULT (getutcdate()),
	  [userName]   [varchar](50) NULL,
    --
    CONSTRAINT tagLinks_PK PRIMARY KEY CLUSTERED (tagLinkID)
  )
END
GO


--drop table dbo.markerTypeCategories
IF OBJECT_ID('dbo.markerTypeCategories') IS NULL
BEGIN
  CREATE TABLE dbo.markerTypeCategories
  (
	  [categoryID]   [smallint] IDENTITY(1,1) NOT NULL,
	  [markerTypeID] [int] NULL,
	  [title]        [nvarchar](500) NULL,
	  [description]  [nvarchar](max) NULL,
	  [Idx]          [smallint] NULL,
    --
    CONSTRAINT PK_markerTypeCategories PRIMARY KEY CLUSTERED (categoryID)
  )
END
GO


--drop table dbo.markerTypes
IF OBJECT_ID('dbo.markerTypes') IS NULL
BEGIN
  CREATE TABLE dbo.markerTypes
  (
	  [markerTypeID]     [smallint] IDENTITY(1,1) NOT NULL,
	  [dateTimeCreated]  [smalldatetime] NULL CONSTRAINT [DF_markerTypes_markerTypeDateTimeCreated]  DEFAULT (getutcdate()),
	  [userID]           [int] NULL,
	  [productID]        [smallint] NULL,
	  [title]            [nvarchar](500) NULL,
	  [description]      [nvarchar](max) NULL,
	  [includeTime]      [bit] NULL CONSTRAINT [DF_markerTypes_includeTime]  DEFAULT ((0)),
	  [private]          [bit] NULL CONSTRAINT [DF_markerTypes_private]  DEFAULT ((0)),
    --
    CONSTRAINT PK_markerTypes PRIMARY KEY CLUSTERED (markerTypeID)
  )
END
GO


--drop table dbo.markers
IF OBJECT_ID('dbo.markers') IS NULL
BEGIN
  CREATE TABLE dbo.markers
  (
	  [markerID]         [int] IDENTITY(1,1) NOT NULL,
	  [typeID]           [smallint] NULL,
	  [dateTimeCreated]  [smalldatetime] NULL CONSTRAINT [DF_markers_markerDateTimeCreated]  DEFAULT (getutcdate()),
	  [userIDCreated]    [int] NULL,
	  [dateTimeEdited]   [smalldatetime] NULL CONSTRAINT [DF_markers_dateTimeEdited]  DEFAULT (getutcdate()),
	  [userIDEdited]     [int] NULL,
	  [title]            [nvarchar](500) NULL,
	  [description]      [nvarchar](max) NULL,
	  [dateTime]         [smalldatetime] NULL,
	  [productID]        [smallint] NULL,
	  [categoryID]       [smallint] NULL,
	  [url]              [varchar](500) NULL,
	  [deleted]          [bit] NULL CONSTRAINT [DF_markers_deleted]  DEFAULT ((0)),
	  [userNameCreated]  [varchar](50) NULL,
	  [userNameEdited]   [varchar](50) NULL,
	  [important]        [bit] NULL CONSTRAINT [DF_markers_important]  DEFAULT ((0)),
    --
    CONSTRAINT PK_markers PRIMARY KEY CLUSTERED (markerID)
  )

  CREATE NONCLUSTERED INDEX IX_markers_Type ON dbo.markers (typeID)
END
GO


IF OBJECT_ID('dbo.markerColumnValues') IS NULL
BEGIN
    CREATE TABLE dbo.markerColumnValues
    (
	    [markerColumnValueID] [int] IDENTITY(1,1) NOT NULL,
	    [markerColumnID] [int] NULL,
	    [markerID] [int] NULL,
	    [userID] [int] NULL,
	    [value] [nvarchar](500) NULL
    )
END
GO


IF OBJECT_ID('dbo.markerTypeColumns') IS NULL
BEGIN
    CREATE TABLE dbo.markerTypeColumns
    (
	    [markerColumnID] [int] IDENTITY(1,1) NOT NULL,
	    [markerTypeID] [int] NULL,
	    [type] [smallint] NULL,
	    [title] [nvarchar](500) NULL,
	    [description] [nvarchar](max) NULL,
	    [defaultValue] [varchar](50) NULL
    )
END
GO


--drop table dbo.pageViews
IF OBJECT_ID('dbo.pageViews') IS NULL
BEGIN
  CREATE TABLE dbo.pageViews
  (
	  [viewID]         [int] IDENTITY(1,1) NOT NULL,
	  [dateTime]       [datetime] NULL CONSTRAINT [DF_pageViews_dateTime]  DEFAULT (getutcdate()),
	  [method]         [varchar](50) NULL,
	  [counterID]      [int] NULL,
	  [collectionID]   [int] NULL,
	  [contextNumber]  [int] NULL,
	  [url]            [varchar](512) NULL,
	  [userName]       [varchar](50) NULL,
	  [hostName]       [varchar](50) NULL,
	  [ipNumber]       [varchar](50) NULL,
	  [agent]          [varchar](512) NULL,
	  [dashboardID]    [int] NULL
  )

  CREATE UNIQUE CLUSTERED INDEX IdxPageViews ON dbo.pageViews (viewID)

  CREATE NONCLUSTERED INDEX IdxPageViews_CollectionID ON dbo.pageViews (collectionID, [dateTime])

  CREATE NONCLUSTERED INDEX IdxPageViews_CounterID ON dbo.pageViews (counterID, [dateTime])

  CREATE NONCLUSTERED INDEX IdxPageViews_Method ON dbo.pageViews (method, counterID, collectionID, [dateTime])

  CREATE NONCLUSTERED INDEX IdxPageViews_UserName ON dbo.pageViews (userName)
END
GO
--insert into dbo.pageViews (counterID) values (null)



IF OBJECT_ID('dbo.GetMissingCounterDays') IS NOT NULL
  DROP PROCEDURE dbo.GetMissingCounterDays
GO
CREATE PROCEDURE dbo.GetMissingCounterDays
  @numDays int=30
AS
	SET NOCOUNT ON
	DECLARE @cursor CURSOR
	DECLARE @counterID int
  DECLARE @sourceType varchar(20)
	DECLARE @dt date
	DECLARE @found int = NULL
  DECLARE @eventDate smalldatetime
	DECLARE @ret TABLE (counterID int, counterDate date, lastRunDate smalldatetime)
	SET @cursor = CURSOR LOCAL FAST_FORWARD
	 FOR
	 SELECT counterID, sourceType FROM zmetric.counters WHERE obsolete = 0 AND published = 1
	 OPEN @cursor
	   FETCH NEXT FROM @cursor INTO @counterID, @sourceType
	   WHILE @@FETCH_STATUS = 0
	   BEGIN
		 SET @dt = DateAdd(d, -1, GetUtcDate())
		 WHILE DateDiff(d, GetUtcDate()-@numDays-1, @dt) > 0
		 BEGIN
			SET @found = NULL
			SELECT TOP 1 @found=counterID FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate = @dt
      IF @found IS NULL
        SELECT TOP 1 @found=counterID FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate = @dt
      IF @found IS NULL
        SELECT TOP 1 @found=counterID FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate = @dt
      IF @found IS NULL
        SELECT TOP 1 @found=counterID FROM zmetric.simpleCounters WHERE counterID = @counterID AND counterDate = @dt
      IF @found IS NULL
        SELECT TOP 1 @found=counterID FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate = @dt
        
			IF @found IS NULL
      BEGIN
      IF @sourceType = 'DOOBJOB'
      BEGIN
      SELECT TOP 1 @eventDate=eventDate 
        FROM zsystem.eventsEx e
          INNER JOIN zmetric.counters c ON e.eventText LIKE c.source + '%' AND c.counterID = @counterID
       WHERE eventTypeID = 23
       ORDER BY e.eventID DESC
      END
      ELSE
      BEGIN
      SELECT TOP 1 @eventDate=eventDate 
        FROM zsystem.eventsEx e
          INNER JOIN zmetric.counters c ON c.procedureName = e.eventText AND c.counterID = @counterID
       WHERE eventTypeID = 2000000003
       ORDER BY e.eventID DESC
       END
       --IF @eventDate < zutil.DateDay(GETUTCDATE()) -- if the counter has run we skip it, it's probably meant to be empty
			 INSERT INTO @ret (counterID, counterDate, lastRunDate) VALUES (@counterID, @dt, @eventDate)
      END
			SET @dt = DateAdd(d, -1, @dt)
		 END
		 FETCH NEXT FROM @cursor INTO @counterID, @sourceType
	   END

	SELECT *
	  FROM @ret r
      INNER JOIN zmetric.countersEx c ON c.counterID = r.counterID
	 ORDER BY r.lastRunDate ASC
GO



--
-- metric
--

IF SCHEMA_ID('metric') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA metric'
GO



IF OBJECT_ID('metric.GetDates') IS NOT NULL
  DROP PROCEDURE metric.GetDates
GO
CREATE PROCEDURE metric.GetDates
  @counterDate  date  OUTPUT,
  @fromDate     datetime2(0) = NULL  OUTPUT,
  @toDate       datetime2(0) = NULL  OUTPUT
AS
  -- This proc gives the correct @counterDate, @fromDate and @toDate for both EVE Metrics and CEVE Metrics
  -- For EVE Metrics @fromDate and @toDate will be YYYY-MM-DD 00:00:00 and YYYY-MM-DD 23:59:59
  -- For CEVE Metrics @fromDate and @toDate will be YYYY-MM-DD 16:00:00 and  YYYY-MM-DD 15:59:59
  SET NOCOUNT ON

  DECLARE @hoursOffset smallint = zsystem.Settings_Value('DateTime', 'UTC-Hours-Offset')

  IF @counterDate IS NULL
  BEGIN
    DECLARE @eventDate datetime2(0)

    SET @eventDate = GETDATE() -- *** *** ***

    IF @hoursOffset != 0
      SET @eventDate = DATEADD(hour, @hoursOffset, @eventDate)

    SET @counterDate = DATEADD(day, -1, @eventDate)
  END

  SET @fromDate = @counterDate
  SET @toDate = DATEADD(day, 1, @counterDate)
  SET @toDate = DATEADD(second, -1, @toDate)

  IF @hoursOffset != 0
  BEGIN
    SET @fromDate = DATEADD(hour, -@hoursOffset, @fromDate)
    SET @toDate = DATEADD(hour, -@hoursOffset, @toDate)
  END
GO



IF OBJECT_ID('metric.Tags_UserStarred') IS NOT NULL
  DROP PROCEDURE metric.Tags_UserStarred
GO
CREATE PROCEDURE metric.Tags_UserStarred
  @userName   varchar(50)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @tagID int
  SELECT @tagID = tagID FROM dbo.tags WHERE tagName = 'STARRED'

  SELECT linkType, linkID, restricted=0 FROM dbo.tagLinks WHERE tagID = @tagID AND userName = @userName ORDER BY linkType, linkID
GO
GRANT EXEC ON metric.Tags_UserStarred TO zzp_server
GO



IF OBJECT_ID('metric.collections') IS NULL
BEGIN
  CREATE TABLE metric.collections
  (
    collectionID              int                                          NOT NULL  IDENTITY(1, 1),
    collectionName            nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    groupID                   smallint                                     NULL,
    [description]             nvarchar(max)                                NULL,
    [order]                   smallint                                     NOT NULL  DEFAULT 0,
    createDate                datetime                                     NOT NULL  DEFAULT GETUTCDATE(),  -- *** web2py does not support datetime2(0) ***
    dynamicCounterID          smallint                                     NULL,
    dynamicSubjectID          int                                          NULL,
    dynamicAggregateFunction  varchar(20)                                  NULL,
    dynamicCount              tinyint                                      NULL,
    userName                  varchar(200)                                 NULL,
    config                    varchar(max)                                 NULL,
    --
    CONSTRAINT collections_PK PRIMARY KEY CLUSTERED (collectionID)
  )
END
GRANT SELECT ON metric.collections TO zzp_server
GO



IF OBJECT_ID('metric.collectionsEx') IS NOT NULL
  DROP VIEW metric.collectionsEx
GO
CREATE VIEW metric.collectionsEx
AS
  SELECT C.groupID, G.groupName, C.collectionID, C.collectionName, C.[description], groupOrder = G.[order], C.[order]
    FROM metric.collections C
      LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
GO
GRANT SELECT ON metric.collectionsEx TO zzp_server
GO



IF OBJECT_ID('metric.collectionCounters') IS NULL
BEGIN
  CREATE TABLE metric.collectionCounters
  (
    collectionCounterID  int            NOT NULL  IDENTITY(1, 1),
    collectionID         int            NOT NULL,
    collectionIndex      smallint       NOT NULL,
    counterID            smallint       NOT NULL,
    subjectID            int            NOT NULL,
    keyID                int            NOT NULL,
    label                nvarchar(200)  NULL, -- Used f.e. in dashboard on EVE Metrics
    aggregateFunction    varchar(20)    NULL, -- Used f.e. in dashboard on EVE Metrics (AVG/SUM/MAX/MIN/LAST)
    severityThreshold    float          NULL, -- Used f.e. in dashboard on EVE Metrics
    goal                 float          NULL, -- Used f.e. in dashboard on EVE Metrics
    goalType             char(1)        NULL, -- Used f.e. in dashboard on EVE Metrics (P:Percentage, V:Value)
    goalDirection        char(1)        NULL, -- Used f.e. in dashboard on EVE Metrics (U:Up, D:Down)
    config               varchar(max)   NULL,
    --
    CONSTRAINT collectionCounters_PK PRIMARY KEY CLUSTERED (collectionCounterID)
  )

  CREATE NONCLUSTERED INDEX collectionCounters_IX_CollectionIndex ON metric.collectionCounters (collectionID, collectionIndex)
END
GRANT SELECT ON metric.collectionCounters TO zzp_server
GO



IF OBJECT_ID('metric.collectionCountersEx') IS NOT NULL
  DROP VIEW metric.collectionCountersEx
GO
CREATE VIEW metric.collectionCountersEx
AS
  SELECT CC.collectionCounterID, collectionGroupID = O.groupID, collectionGroupName = OG.groupName, CC.collectionID, O.collectionName, CC.collectionIndex,
         counterGroupID = C.groupID, counterGroupName = CG.groupName, CC.counterID, C.counterName,
         CC.subjectID, subjectText = COALESCE(L.columnName, LS.[fullText], LS.lookupText),
         CC.keyID, keyText = ISNULL(LK.[fullText], LK.lookupText),
         CC.label, CC.aggregateFunction, CC.severityThreshold, CC.goal, CC.goalType, CC.goalDirection
    FROM metric.collectionCounters CC
      LEFT JOIN metric.collections O ON O.collectionID = CC.collectionID
        LEFT JOIN zmetric.groups OG ON OG.groupID = O.groupID
      LEFT JOIN zmetric.counters C ON C.counterID = CC.counterID
        LEFT JOIN zmetric.groups CG ON CG.groupID = C.groupID
        LEFT JOIN zsystem.lookupValues LS ON LS.lookupTableID = C.subjectLookupTableID AND LS.lookupID = CC.subjectID
        LEFT JOIN zsystem.lookupValues LK ON LK.lookupTableID = C.keyLookupTableID AND LK.lookupID = CC.keyID
      LEFT JOIN zmetric.columns L ON L.counterID = CC.counterID AND CONVERT(int, L.columnID) = CC.subjectID
GO
GRANT SELECT ON metric.collectionCountersEx TO zzp_server
GO



IF OBJECT_ID('metric.dashboards') IS NULL
BEGIN
  CREATE TABLE metric.dashboards
  (
    dashboardID    int            NOT NULL  IDENTITY(1,1),
    dashboardName  varchar(50)    NULL,
    description    varchar(4000)  NULL,
    groupID        smallint       NULL,
    userName       varchar(50)    NULL,
    createDate     smalldatetime  NULL  DEFAULT GETUTCDATE(),
    collections    varchar(1000)  NULL,
    numDays        smallint       NULL  DEFAULT 7,
    config         varchar(max)   NULL,
    --
    CONSTRAINT dashboards_PK PRIMARY KEY CLUSTERED (dashboardID)
  )
END
GO



IF OBJECT_ID('metric.dashboardsEx') IS NOT NULL
  DROP VIEW metric.dashboardsEx
GO
CREATE VIEW metric.dashboardsEx
AS
  SELECT d.dashboardID, d.dashboardName, d.[description], d.groupID, d.userName, d.createDate, d.collections, d.numDays, d.config, g.groupName
    FROM metric.dashboards d
      LEFT JOIN zmetric.groups g ON g.groupID = d.groupID
GO
GRANT SELECT ON metric.dashboardsEx TO zzp_server
GO


IF OBJECT_ID('metric.accessRules') IS NULL
BEGIN
  CREATE TABLE metric.accessRules
  (
    accessRuleID       int           NOT NULL  IDENTITY(1, 1),
    fullName           nvarchar(50)  NULL,
    emailAddress       varchar(50)   NULL,
    mailingList        bit           NULL,
    createDate         datetime      NULL  DEFAULT GETUTCDATE(),
    createdByUserName  varchar(50)   NULL,
    contentType        varchar(12)   NULL,
    contentID          int           NULL,
    --
    CONSTRAINT accessRules_PK PRIMARY KEY CLUSTERED (accessRuleID)
  )
END
GO




IF OBJECT_ID('metric.digests') IS NULL
BEGIN
  CREATE TABLE metric.digests
  (
    digestID         int            NOT NULL  IDENTITY(1, 1),
    digestName       nvarchar(50)   NULL,
    [description]    nvarchar(max)  NULL,
    createDate       smalldatetime  NULL  DEFAULT GETUTCDATE(),
    modifyDate       smalldatetime  NULL  DEFAULT GETUTCDATE(),
    userName         varchar(50)    NULL,
    emailSubject     nvarchar(500)  NULL,
    emailAddresses   varchar(max)   NULL,
    [disabled]       bit            NULL  DEFAULT 0,
    scheduleType     varchar(10)    NULL,
    scheduleDay      tinyint        NULL,
    onlyAlert        bit            NULL,
    sendDescription  bit            NULL,
    --
    CONSTRAINT digests_PK PRIMARY KEY CLUSTERED (digestID)
  )
END
GO



IF OBJECT_ID('metric.digestSections') IS NULL
BEGIN
  CREATE TABLE metric.digestSections
  (
    sectionID      int             NOT NULL  IDENTITY(1, 1),
    digestID       int             NULL,
    sectionTitle   nvarchar(500)   NULL,
    [description]  nvarchar(4000)  NULL,
    position       tinyint         NULL,
    contentType    varchar(50)     NULL,
    contentID      int             NULL,
    contentConfig  varchar(1000)   NULL,
    width          int             NULL,
    height         int             NULL,
    zoom           float           NULL,
    templateID     int             NULL,
    --
    CONSTRAINT digestSections_PK PRIMARY KEY CLUSTERED (sectionID)
  )

  CREATE NONCLUSTERED INDEX digestSections_IX_Digest ON metric.digestSections (digestID)
END
GO



IF OBJECT_ID('metric.digestSectionTemplates') IS NULL
BEGIN
  CREATE TABLE metric.digestSectionTemplates
  (
    templateID       int          NOT NULL  IDENTITY(1, 1),
    templateName     varchar(50)  NULL,
    icon             varchar(50)  NULL,
    backgroundColor  varchar(16)  NULL,
    color            varchar(16)  NULL,
    templateType     varchar(10)  NULL,
    fontSize         int          NULL,
    iconPosition     varchar(10)  NULL,
    --
    CONSTRAINT digestSectionTemplates_PK PRIMARY KEY CLUSTERED (templateID)
  )
END
GO



IF OBJECT_ID('metric.digestAlerts') IS NULL
BEGIN
  CREATE TABLE metric.digestAlerts
  (
    alertID        int             NOT NULL  IDENTITY(1, 1),
    digestID       int             NOT NULL,
    alertTitle     nvarchar(500)   NULL,
    [description]  nvarchar(4000)  NULL,
    position       int             NULL,
    counterID      smallint        NOT NULL,
    subjectID      int             NULL,
    keyID          int             NULL,
    method         varchar(16)     NOT NULL,
    value          float           NULL,
    config         varchar(1000)   NULL,
    severity       tinyint         NULL  DEFAULT 3,
    templateID     int             NULL,
    --
    CONSTRAINT digestAlerts_PK PRIMARY KEY CLUSTERED (alertID)
  )

  CREATE NONCLUSTERED INDEX digestAlerts_IX_Digest ON metric.digestAlerts (digestID)
END
GO



IF OBJECT_ID('metric.digestEmails') IS NULL
BEGIN
  CREATE TABLE metric.digestEmails
  (
    digestEmailID      int            NOT NULL  IDENTITY(1, 1),
    digestID           int            NOT NULL,
    emailAddress       varchar(50)    NOT NULL,
    createdByUserName  varchar(50)    NOT NULL,
    createDate         smalldatetime  NULL      DEFAULT GETUTCDATE(),
    mailingList        bit            NULL      DEFAULT 0,
    cc                 bit            NULL      DEFAULT 0,
    fullName           nvarchar(50)   NULL,
    --
    CONSTRAINT digestEmails_PK PRIMARY KEY CLUSTERED (digestEmailID)
  )

  CREATE NONCLUSTERED INDEX digestEmails_IX_Digest ON metric.digestEmails (digestID)
END
GO


IF OBJECT_ID('metric.sourceTypes') IS NULL
BEGIN
  CREATE TABLE metric.sourceTypes
  (
    sourceType      varchar(20)    NOT NULL,
    sourceTypeText  nvarchar(100)  NOT NULL,
    [description]   nvarchar(max)  NULL,
    --
    CONSTRAINT sourceTypes_PK PRIMARY KEY CLUSTERED (sourceType)
  )

  INSERT INTO metric.sourceTypes (sourceType, sourceTypeText, [description]) VALUES ('DB', 'Database', 'Normal database counters.  Procs executed after restore of production DB.')
  INSERT INTO metric.sourceTypes (sourceType, sourceTypeText, [description]) VALUES ('OTHER', 'Other', 'Other special counters.')
END
GO



IF OBJECT_ID('metric.Counters_Stats') IS NOT NULL
  DROP PROCEDURE metric.Counters_Stats
GO
CREATE PROCEDURE metric.Counters_Stats
  @counterID  smallint
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @counterTable nvarchar(256), @firstDate date, @lastDate date, @count10000 int

  SELECT @counterTable = counterTable FROM zmetric.counters WHERE counterID = @counterID

  IF @counterTable = 'zmetric.keyCounters'
  BEGIN
    SELECT TOP 1 @firstDate = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID ORDER BY counterDate

    SELECT TOP 1 @lastDate = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID ORDER BY counterDate DESC

    SELECT @count10000 = (SELECT COUNT(*) FROM (SELECT TOP 10000 counterID FROM zmetric.keyCounters WHERE counterID = @counterID) X)
  END
  ELSE
  BEGIN
    SELECT TOP 1 @firstDate = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID ORDER BY counterDate

    SELECT TOP 1 @lastDate = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID ORDER BY counterDate DESC

    SELECT @count10000 = (SELECT COUNT(*) FROM (SELECT TOP 10000 counterID FROM zmetric.dateCounters WHERE counterID = @counterID) X)
  END

  SELECT firstDate = @firstDate, lastDate = @lastDate, count10000 = @count10000
GO
GRANT EXEC ON metric.Counters_Stats TO zzp_server
GO



IF OBJECT_ID('metric.Counters_GraphText') IS NOT NULL
  DROP PROCEDURE metric.Counters_GraphText
GO
CREATE PROCEDURE metric.Counters_GraphText
  @counterID  smallint,
  @subjectID  int,
  @keyID      int
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  DECLARE @subjectText nvarchar(1000), @keyText nvarchar(1000), @columnName nvarchar(200)

  DECLARE @subjectLookupTableID int, @keyLookupTableID int

  SELECT @subjectLookupTableID = subjectLookupTableID, @keyLookupTableID = keyLookupTableID FROM zmetric.counters WHERE counterID = @counterID

  IF @subjectLookupTableID IS NOT NULL AND @keyLookupTableID IS NOT NULL
  BEGIN
    SELECT @subjectText = ISNULL([fullText], lookupText) FROM zsystem.lookupValues WHERE lookupTableID = @subjectLookupTableID AND lookupID = @subjectID

    SELECT @keyText = ISNULL([fullText], lookupText) FROM zsystem.lookupValues WHERE lookupTableID = @keyLookupTableID AND lookupID = @keyID
  END
  ELSE IF @keyLookupTableID IS NOT NULL
  BEGIN
    SELECT @keyText = ISNULL([fullText], lookupText) FROM zsystem.lookupValues WHERE lookupTableID = @keyLookupTableID AND lookupID = @keyID

    IF @subjectID BETWEEN 0 AND 255
      SELECT @columnName = columnName FROM zmetric.columns WHERE counterID = @counterID AND columnID = CONVERT(tinyint, @subjectID)
  END
  ELSE
  BEGIN
    IF @subjectID BETWEEN 0 AND 255
      SELECT @columnName = columnName FROM zmetric.columns WHERE counterID = @counterID AND columnID = CONVERT(tinyint, @subjectID)
  END

  SELECT subjectText = @subjectText, keyText = @keyText, columnName = @columnName
GO
GRANT EXEC ON metric.Counters_GraphText TO zzp_server
GO



IF OBJECT_ID('metric.DateCounters_Diff') IS NOT NULL
  DROP PROCEDURE metric.DateCounters_Diff
GO
CREATE PROCEDURE metric.DateCounters_Diff
  @counterID     smallint,
  @counterDate   date = NULL,
  @subjectID     int = 0,
  @diffDays      smallint = 7,
  @order         char(1) = 'P', -- P:Percentage, C:Count
  @excludeCount  int = 1000,
  @rows          smallint = 100,
  @ascending     bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC metric.GetDates @counterDate OUTPUT

  DECLARE @diffDate date
  SET @diffDate = DATEADD(day, -@diffDays, @counterDate)

  DECLARE @lookupTableID int, @counterTable nvarchar(256)
  SELECT @lookupTableID = keyLookupTableID, @counterTable = counterTable FROM zmetric.counters WHERE counterID = @counterID

  DECLARE @stmt nvarchar(max)
  IF @counterTable = 'zmetric.keyCounters'
  BEGIN
    SET @stmt = '
      SELECT TOP (@pRows) A.keyID, keyText = ISNULL(L.[fullText], L.lookupText), A.value,
             oldValue = ISNULL(B.value, 0), diffCount = A.value - ISNULL(B.value, 0), diffPercentage = A.value / ISNULL(B.value, 1)
        FROM zmetric.keyCounters A
          LEFT JOIN zmetric.keyCounters B ON B.counterID = A.counterID AND B.counterDate = @pDiffDate AND B.columnID = A.columnID AND B.keyID = A.keyID
          LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = @pLookupTableID AND L.lookupID = A.keyID
       WHERE A.counterID = @pCounterID AND A.counterDate = @pCounterDate AND A.columnID = @pSubjectID AND A.value > @pExcludeCount
       ORDER BY '
  END
  ELSE
  BEGIN
    SET @stmt = '
      SELECT TOP (@pRows) A.keyID, keyText = ISNULL(L.[fullText], L.lookupText), A.value,
             oldValue = ISNULL(B.value, 0), diffCount = A.value - ISNULL(B.value, 0), diffPercentage = A.value / ISNULL(B.value, 1)
        FROM zmetric.dateCounters A
          LEFT JOIN zmetric.dateCounters B ON B.counterID = A.counterID AND B.counterDate = @pDiffDate AND B.subjectID = A.subjectID AND B.keyID = A.keyID
          LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = @pLookupTableID AND L.lookupID = A.keyID
       WHERE A.counterID = @pCounterID AND A.counterDate = @pCounterDate AND A.subjectID = @pSubjectID AND A.value > @pExcludeCount
       ORDER BY '
  END

  IF @order = 'C'
    SET @stmt = @stmt + '5'
  ELSE
    SET @stmt = @stmt + '6'

  IF @ascending = 0
    SET @stmt = @stmt + ' DESC'

  EXEC sp_executesql @stmt, N'@pCounterID smallint, @pcounterDate date, @pSubjectID int, @pExcludeCount int, @pRows smallint, @pDiffDate date, @pLookupTableID int',
                     @pCounterID = @counterID, @pcounterDate = @counterDate, @pSubjectID = @subjectID, @pExcludeCount = @excludeCount, @pRows = @rows,
                     @pDiffDate = @diffDate, @pLookupTableID = @lookupTableID
GO
GRANT EXEC ON metric.DateCounters_Diff TO zzp_server
GO



IF OBJECT_ID('metric.Counters_DateGraph') IS NOT NULL
  DROP PROCEDURE metric.Counters_DateGraph
GO
CREATE PROCEDURE metric.Counters_DateGraph
  @counterID  smallint,
  @subjectID  int,
  @keyID      int,
  @aggregate  varchar(100) = 'DateDay', -- DateDay/DateWeek/DateMonth/Sundays/DateWeekByDay
  @days       smallint = 365,
  @fromDate   date = NULL,
  @toDate     date = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SET @days = ISNULL(@days, 0)
  IF @days = 0 SET @days = 32767

  IF @fromDate IS NULL AND @toDate IS NULL
  BEGIN
    -- Not using metric.GetDates because of dependency on ebs_RESEARCH, this proc should work even when ebs_RESEARCH is not available
    SELECT TOP 1 @toDate = counterDate FROM zmetric.dateCounters WHERE counterID = 1 ORDER BY counterDate DESC
    IF @toDate IS NULL
      SET @toDate = DATEADD(day, -1, GETDATE())

    SET @fromDate = DATEADD(day, -(@days - 1), @toDate)
    -- To display more recent data added hourly by Hadoop
    SET @toDate = DATEADD(day, 1, @toDate)
  END
  ELSE IF @fromDate IS NULL
    SET @fromDate = DATEADD(day, -(@days - 1), @toDate)
  ELSE IF @toDate IS NULL
    SET @toDate = DATEADD(day, @days - 1, @fromDate)

  DECLARE @counterDate nvarchar(100), @value nvarchar(100), @groupBy nvarchar(100), @where nvarchar(100)

  DECLARE @counterTable nvarchar(256), @absoluteValue bit
  SELECT @counterTable = counterTable, @absoluteValue = absoluteValue FROM zmetric.counters WHERE counterID = @counterID

  IF @aggregate = 'DateDay'
  BEGIN
    SET @counterDate = 'counterDate'
    SET @value = 'value'
  END
  ELSE IF @aggregate = 'DateWeek'
  BEGIN
    SET @counterDate = 'zutil.DateWeek(counterDate)'
    IF @absoluteValue = 1 SET @value = 'AVG(value)' ELSE SET @value = 'SUM(value)'
    SET @groupBy = 'zutil.DateWeek(counterDate)'
  END
  ELSE IF @aggregate = 'DateMonth'
  BEGIN
    SET @counterDate = 'zutil.DateMonth(counterDate)'
    IF @absoluteValue = 1 SET @value = 'AVG(value)' ELSE SET @value = 'SUM(value)'
    SET @groupBy = 'zutil.DateMonth(counterDate)'
  END
  ELSE IF @aggregate = 'Sundays'
  BEGIN
    SET @counterDate = 'counterDate'
    SET @value = 'value'
    SET @where = 'DATEPART(dw, counterDate) = 1'
  END
  ELSE IF @aggregate = 'DateWeekByDay'
  BEGIN
    SET @counterDate = 'zutil.DateWeek(counterDate)'
    IF @absoluteValue = 1 SET @value = 'AVG(value) / 7' ELSE SET @value = 'SUM(value) / 7'
    SET @groupBy = 'zutil.DateWeek(counterDate)'
  END
  ELSE
  BEGIN
    RAISERROR ('@aggregate not valid', 16, 1)
    RETURN -1
  END

  DECLARE @sql nvarchar(max)

  SET @sql = 'SELECT DT = ' + @counterDate + ', VAL = ' + @value

  IF @counterTable = 'zmetric.keyCounters'
  BEGIN
    SET @sql = 'SELECT DT = ' + @counterDate + ', VAL = ' + @value
             + ' FROM zmetric.keyCounters'
             + ' WHERE counterID = @p_counterID AND columnID = @p_columnID AND keyID = @p_keyID AND counterDate BETWEEN @p_fromDate AND @p_toDate'
             + CASE WHEN @where IS NOT NULL THEN ' AND ' + @where ELSE '' END
             + CASE WHEN @groupBy IS NOT NULL THEN ' GROUP BY ' + @groupBy ELSE '' END
             + ' ORDER BY 1'

    EXEC sp_executesql @sql, N'@p_counterID smallint, @p_columnID tinyint, @p_keyID int, @p_fromDate date, @p_toDate date',
                       @p_counterID = @counterID, @p_columnID = @subjectID, @p_keyID = @keyID, @p_fromDate = @fromDate, @p_toDate = @toDate
  END
  ELSE
  BEGIN
    SET @sql = 'SELECT DT = ' + @counterDate + ', VAL = ' + @value
             + ' FROM zmetric.dateCounters'
             + ' WHERE counterID = @p_counterID AND subjectID = @p_subjectID AND keyID = @p_keyID AND counterDate BETWEEN @p_fromDate AND @p_toDate'
             + CASE WHEN @where IS NOT NULL THEN ' AND ' + @where ELSE '' END
             + CASE WHEN @groupBy IS NOT NULL THEN ' GROUP BY ' + @groupBy ELSE '' END
             + ' ORDER BY 1'

    EXEC sp_executesql @sql, N'@p_counterID smallint, @p_subjectID int, @p_keyID int, @p_fromDate date, @p_toDate date',
                       @p_counterID = @counterID, @p_subjectID = @subjectID, @p_keyID = @keyID, @p_fromDate = @fromDate, @p_toDate = @toDate
  END
GO
GRANT EXEC ON metric.Counters_DateGraph TO zzp_server
GO



IF OBJECT_ID('metric.CollectionDashboardView') IS NOT NULL
  DROP PROCEDURE metric.CollectionDashboardView
GO
CREATE PROCEDURE metric.CollectionDashboardView
  @collectionID  int,
  @counterDate   date = NULL,
  @days          smallint = 7,  -- 1/7/30/90
  @return6to8    bit = 0,
  @calendar      bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    DECLARE @cursor CURSOR

    IF @days NOT IN (1, 7, 30, 90)
      RAISERROR ('@days not valid', 16, 1)

    -- Not using metric.GetDates because of dependency on ebs_RESEARCH, this proc should work even when ebs_RESEARCH is not available
    IF @counterDate IS NULL
      SELECT TOP 1 @counterDate = counterDate FROM zmetric.dateCounters WHERE counterID = 1 ORDER BY counterDate DESC
    IF @counterDate IS NULL
      SET @counterDate = DATEADD(day, -1, GETDATE())

    DECLARE @lastDayOfWeek date, @lastDayOfMonth date
    IF @calendar = 1
    BEGIN
      SET @lastDayOfWeek = DATEADD(day, 6, zutil.DateWeek(@counterDate))
      SET @lastDayOfMonth = DATEADD(day, -1, DATEADD(month, 1, zutil.DateMonth(@counterDate)))
    END

    CREATE TABLE #dashboard
    (
      collectionIndex       smallint        IDENTITY(1, 1)  PRIMARY KEY,
      groupID               smallint,
      groupName             nvarchar(200),
      counterID             smallint,
      counterName           nvarchar(200),
      counterTable          nvarchar(256),
      subjectID             int,
      subjectText           nvarchar(1000),
      keyID                 int,
      keyText               nvarchar(1000),
      subjectLookupTableID  int,
      keyLookupTableID      int,
      absoluteValue         bit,
      units                 varchar(20),
      aggregateFunction    varchar(20),
      label                nvarchar(200),
      severityThreshold    float,
      goal                 float,
      goalType             char(1),
      goalDirection        char(1),
      date8                 date,
      value8                float,
      date7                 date,
      value7                float,
      date6                 date,
      value6                float,
      date5                 date,
      value5                float,
      date4                 date,
      value4                float,
      date3                 date,
      value3                float,
      date2                 date,
      value2                float,
      date1                 date,
      value1                float
    )

    DECLARE @maxColumnIndex tinyint = 5
    IF @return6to8 = 1 SET @maxColumnIndex = 8

    DECLARE @fromDate date, @toDate date, @counterTable nvarchar(256)

    DECLARE @dynamicCounterID smallint, @dynamicSubjectID int, @dynamicAggregateFunction varchar(20), @dynamicCount tinyint
    SELECT @dynamicCounterID = dynamicCounterID, @dynamicSubjectID = dynamicSubjectID, @dynamicAggregateFunction = dynamicAggregateFunction, @dynamicCount = dynamicCount
      FROM metric.collections
     WHERE collectionID = @collectionID
    IF @dynamicCounterID IS NULL
    BEGIN
      -- Normal collection
      INSERT INTO #dashboard (groupID, groupName, counterID, counterName, counterTable, subjectID, keyID,
                              subjectLookupTableID, keyLookupTableID, absoluteValue, units,
                              aggregateFunction, label, severityThreshold, goal, goalType, goalDirection)
           SELECT C.groupID, G.groupName, CC.counterID, C.counterName, C.counterTable, CC.subjectID, CC.keyID,
                  C.subjectLookupTableID, C.keyLookupTableID, C.absoluteValue, C.units,
                  ISNULL(CC.aggregateFunction, 'AVG'), CC.label, CC.severityThreshold, CC.goal, CC.goalType, CC.goalDirection
             FROM metric.collectionCounters CC
               INNER JOIN zmetric.counters C ON C.counterID = CC.counterID
                 LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
            WHERE CC.collectionID = @collectionID
            ORDER BY CC.collectionIndex
    END
    ELSE
    BEGIN
      -- Dynamic collection (*** *** *** Finding counters is only done using SUM *** *** ***)
      SET @toDate = @counterDate
      SET @fromDate = DATEADD(day, -(@days - 1), @toDate)

      DECLARE @groupID smallint, @groupName nvarchar(200), @counterName nvarchar(200), @lookupTableID int, @absoluteValue bit, @units varchar(20)
      SELECT @counterName = counterName, @groupID = groupID, @lookupTableID = keyLookupTableID, @absoluteValue = absoluteValue, @units = units, @counterTable = counterTable
        FROM zmetric.counters
       WHERE counterID = @dynamicCounterID
      SELECT @groupName = groupName FROM zmetric.groups WHERE groupID = @groupID

      IF @counterTable = 'zmetric.keyCounters'
      BEGIN
        INSERT INTO #dashboard (groupID, groupName, counterID, counterName, counterTable, subjectID, keyID,
                                subjectLookupTableID, keyLookupTableID, absoluteValue, units,
                                aggregateFunction, label, severityThreshold, goal, goalType, goalDirection)
             SELECT @groupID, @groupName, @dynamicCounterID, @counterName, @counterTable, @dynamicSubjectID, X.keyID, NULL, @lookupTableID, @absoluteValue, @units,
                    @dynamicAggregateFunction, label = ISNULL(LV.[fullText], LV.lookupText), NULL, NULL, NULL, NULL
               FROM (SELECT TOP (@dynamicCount) keyID, sumValue = SUM(value)
                       FROM zmetric.keyCounters
                      WHERE counterID = @dynamicCounterID AND counterDate BETWEEN @fromDate AND @toDate AND columnID = @dynamicSubjectID
                      GROUP BY keyID
                      ORDER BY SUM(value) DESC) X
                 INNER JOIN zsystem.lookupValues LV ON LV.lookupTableID = @lookupTableID AND LV.lookupID = X.keyID
              ORDER BY sumValue DESC
      END
      ELSE
      BEGIN
        INSERT INTO #dashboard (groupID, groupName, counterID, counterName, counterTable, subjectID, keyID,
                                subjectLookupTableID, keyLookupTableID, absoluteValue, units,
                                aggregateFunction, label, severityThreshold, goal, goalType, goalDirection)
             SELECT @groupID, @groupName, @dynamicCounterID, @counterName, @counterTable, @dynamicSubjectID, X.keyID, NULL, @lookupTableID, @absoluteValue, @units,
                    @dynamicAggregateFunction, label = ISNULL(LV.[fullText], LV.lookupText), NULL, NULL, NULL, NULL
               FROM (SELECT TOP (@dynamicCount) keyID, sumValue = SUM(value)
                       FROM zmetric.dateCounters
                      WHERE counterID = @dynamicCounterID AND counterDate BETWEEN @fromDate AND @toDate AND subjectID = @dynamicSubjectID
                      GROUP BY keyID
                      ORDER BY SUM(value) DESC) X
                 INNER JOIN zsystem.lookupValues LV ON LV.lookupTableID = @lookupTableID AND LV.lookupID = X.keyID
              ORDER BY sumValue DESC
      END
    END

    DECLARE @collectionIndex smallint, @counterID smallint, @subjectID int, @keyID int, @subjectLookupTableID int, @keyLookupTableID int, @aggregateFunction varchar(20),
            @subjectLookupText nvarchar(1000), @keyLookupText nvarchar(1000), @columnUnits varchar(20),
            @stmt nvarchar(4000), @value float, @columnIndex tinyint

    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT collectionIndex, counterID, counterTable, subjectID, keyID, subjectLookupTableID, keyLookupTableID, aggregateFunction
            FROM #dashboard
           ORDER BY collectionIndex
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @collectionIndex, @counterID, @counterTable, @subjectID, @keyID, @subjectLookupTableID, @keyLookupTableID, @aggregateFunction
    WHILE @@FETCH_STATUS = 0
    BEGIN
      IF @aggregateFunction NOT IN ('AVG', 'SUM', 'MAX', 'MIN', 'LAST', 'FIRST')
        RAISERROR ('Aggregate function not supported', 16, 1)

      SELECT @subjectLookupText = NULL, @keyLookupText = NULL, @columnUnits = NULL

      IF @dynamicCounterID IS NULL
      BEGIN
        IF @subjectLookupTableID IS NOT NULL
          SELECT @subjectLookupText = lookupText FROM zsystem.lookupValues WHERE lookupTableID = @subjectLookupTableID AND lookupID = @subjectID
        ELSE
        BEGIN
          SELECT @subjectLookupText = columnName, @columnUnits = units
            FROM zmetric.columns
           WHERE counterID = @counterID AND columnID = CONVERT(tinyint, @subjectID)
        END
      END

      IF @keyLookupTableID IS NOT NULL
        SELECT @keyLookupText = lookupText FROM zsystem.lookupValues WHERE lookupTableID = @keyLookupTableID AND lookupID = @keyID

      UPDATE #dashboard
         SET subjectText = @subjectLookupText, keyText = @keyLookupText, units = ISNULL(@columnUnits, units)
       WHERE collectionIndex = @collectionIndex

      SET @columnIndex = 1

      SET @toDate = @counterDate
      IF @calendar = 1 AND @days > 1
      BEGIN
        IF @days = 7
          SET @toDate = @lastDayOfWeek
        ELSE
          SET @toDate = @lastDayOfMonth
      END

      WHILE @columnIndex <= @maxColumnIndex
      BEGIN
        SET @value = NULL

        IF @calendar = 1 AND @days > 7
        BEGIN
          SET @fromDate = zutil.DateMonth(@toDate)
          IF @days = 90
            SET @fromDate = DATEADD(month, -2, @fromDate)
        END
        ELSE
          SET @fromDate = DATEADD(day, -(@days - 1), @toDate)

        -- Dynamic SELECT
        IF @counterTable = 'zmetric.keyCounters'
        BEGIN
          IF @aggregateFunction = 'LAST'
            SET @stmt = 'SELECT TOP 1 @pValue = value FROM zmetric.keyCounters WHERE counterID = @pCounterID AND columnID = @pColumnID AND keyID = @pKeyID AND counterDate BETWEEN @pFromDate AND @pToDate ORDER BY counterDate DESC'
          ELSE IF @aggregateFunction = 'FIRST'
            SET @stmt = 'SELECT TOP 1 @pValue = value FROM zmetric.keyCounters WHERE counterID = @pCounterID AND columnID = @pColumnID AND keyID = @pKeyID AND counterDate BETWEEN @pFromDate AND @pToDate ORDER BY counterDate ASC'
          ELSE
            SET @stmt = 'SELECT @pValue = ' + @aggregateFunction + '(value) FROM zmetric.keyCounters WHERE counterID = @pCounterID AND columnID = @pColumnID AND keyID = @pKeyID AND counterDate BETWEEN @pFromDate AND @pToDate'
          EXEC sp_executesql @stmt, N'@pValue float OUTPUT, @pCounterID smallint, @pColumnID tinyint, @pKeyID int, @pFromDate date, @pToDate date',
                             @pValue = @value OUTPUT, @pCounterID = @counterID, @pColumnID = @subjectID, @pKeyID = @keyID, @pFromDate = @fromDate, @pToDate = @toDate
        END
        ELSE
        BEGIN
          IF @aggregateFunction = 'LAST'
            SET @stmt = 'SELECT TOP 1 @pValue = value FROM zmetric.dateCounters WHERE counterID = @pCounterID AND subjectID = @pSubjectID AND keyID = @pKeyID AND counterDate BETWEEN @pFromDate AND @pToDate ORDER BY counterDate DESC'
          ELSE IF @aggregateFunction = 'FIRST'
            SET @stmt = 'SELECT TOP 1 @pValue = value FROM zmetric.dateCounters WHERE counterID = @pCounterID AND subjectID = @pSubjectID AND keyID = @pKeyID AND counterDate BETWEEN @pFromDate AND @pToDate ORDER BY counterDate ASC'
          ELSE
            SET @stmt = 'SELECT @pValue = ' + @aggregateFunction + '(value) FROM zmetric.dateCounters WHERE counterID = @pCounterID AND subjectID = @pSubjectID AND keyID = @pKeyID AND counterDate BETWEEN @pFromDate AND @pToDate'
          EXEC sp_executesql @stmt, N'@pValue float OUTPUT, @pCounterID smallint, @pSubjectID int, @pKeyID int, @pFromDate date, @pToDate date',
                             @pValue = @value OUTPUT, @pCounterID = @counterID, @pSubjectID = @subjectID, @pKeyID = @keyID, @pFromDate = @fromDate, @pToDate = @toDate
        END

        -- Dynamic UPDATE
        SET @stmt = 'UPDATE #dashboard SET date' + CONVERT(nvarchar, @columnIndex) + ' = @pFromDate, value' + CONVERT(nvarchar, @columnIndex) + ' = @pValue WHERE collectionIndex = @pCollectionIndex'
        EXEC sp_executesql @stmt, N'@pFromDate date, @pValue float, @pCollectionIndex smallint',
                           @pFromDate = @fromDate, @pValue = @value, @pCollectionIndex = @collectionIndex 

        IF @calendar = 1 AND @days > 7
        BEGIN
          IF @days = 30
            SET @toDate = DATEADD(day, -1, DATEADD(month, -1, DATEADD(day, 1, @toDate)))
          ELSE
            SET @toDate = DATEADD(day, -1, DATEADD(month, -3, DATEADD(day, 1, @toDate)))
        END
        ELSE
          SET @toDate = DATEADD(day, -@days, @toDate)

        SET @columnIndex = @columnIndex + 1
      END

      FETCH NEXT FROM @cursor INTO @collectionIndex, @counterID, @counterTable, @subjectID, @keyID, @subjectLookupTableID, @keyLookupTableID, @aggregateFunction
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    SELECT groupID, groupName, counterID, counterName, subjectID, subjectText, keyID, keyText,
           absoluteValue, units, aggregateFunction, label, severityThreshold, goal, goalType, goalDirection,
           date8, value8, date7, value7, date6, value6, date5, value5, date4, value4, date3, value3, date2, value2, date1, value1
      FROM #dashboard
     ORDER BY collectionIndex

    DROP TABLE #dashboard
  END TRY
  BEGIN CATCH
    IF CURSOR_STATUS('variable', '@cursor') > -1
      CLOSE @cursor
    IF CURSOR_STATUS('variable', '@cursor') = -1
      DEALLOCATE @cursor
    EXEC zsystem.CatchError 'metric.CollectionDashboardView'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON metric.CollectionDashboardView TO zzp_server
GO



IF OBJECT_ID('metric.Counters_DeleteData') IS NOT NULL
  DROP PROCEDURE metric.Counters_DeleteData
GO
CREATE PROCEDURE metric.Counters_DeleteData
  @counterID          smallint = NULL,
  @fromDate           date,
  @toDate             date = NULL,
  @counterIdentifier  varchar(500) = NULL
  WITH RECOMPILE
AS
  SET NOCOUNT ON

  BEGIN TRY
    IF @counterID IS NULL
    BEGIN
      IF @counterIdentifier IS NULL
        RAISERROR ('@counterID or @counterIdentifier must be set', 16, 1)

      SET @counterID = zmetric.Counters_ID(@counterIdentifier)
      IF @counterID IS NULL
        RAISERROR ('@counterIdentifier not found', 16, 1)
    END

    IF @fromDate IS NULL
      RAISERROR ('@fromDate must be set', 16, 1)

    -- zmetric.dateCounters / zmetric.keyCounters
    IF @toDate IS NULL
    BEGIN
      DELETE FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate = @fromDate
      DELETE FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate = @fromDate
    END
    ELSE
    BEGIN
      DELETE FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate BETWEEN @fromDate AND @toDate
      DELETE FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate BETWEEN @fromDate AND @toDate
    END

    -- zmetric.keyTimeCounters
    DECLARE @fromDateTime datetime2(0), @toDateTime datetime2(0)
    SET @fromDateTime = @fromDate
    IF @toDate IS NULL
      SET @toDateTime = DATEADD(day, 1, @fromDate)
    ELSE
      SET @toDateTime = DATEADD(day, 1, @toDate)
    SET @toDateTime = DATEADD(second, -1, @toDateTime)
    DELETE FROM zmetric.keyTimeCounters WHERE counterID = @counterID AND counterDate BETWEEN @fromDateTime AND @toDateTime
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.Counters_DeleteData'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON metric.Counters_DeleteData TO zzp_server
GO



IF OBJECT_ID('metric.Counters_Delete') IS NOT NULL
  DROP PROCEDURE metric.Counters_Delete
GO
CREATE PROCEDURE metric.Counters_Delete
  @counterID          smallint = NULL,
  @counterIdentifier  varchar(500) = NULL
AS
  SET NOCOUNT ON

  BEGIN TRY
    IF @counterID IS NULL
    BEGIN
      IF @counterIdentifier IS NULL
        RAISERROR ('@counterID or @counterIdentifier must be set', 16, 1)

      SET @counterID = zmetric.Counters_ID(@counterIdentifier)
      IF @counterID IS NULL
        RAISERROR ('@counterIdentifier not found', 16, 1)
    END

    IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = @counterID)
      RAISERROR ('Counter not found', 16, 1)

    IF EXISTS(SELECT * FROM zmetric.dateCounters WHERE counterID = @counterID)
      RAISERROR ('Delete not allowed, data found in zmetric.dateCounters', 16, 1)

    IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = @counterID)
      RAISERROR ('Delete not allowed, data found in zmetric.keyCounters', 16, 1)    

    IF EXISTS(SELECT * FROM zmetric.keyTimeCounters WHERE counterID = @counterID)
      RAISERROR ('Delete not allowed, data found in zmetric.keyTimeCounters', 16, 1)

    IF EXISTS(SELECT * FROM metric.collections WHERE dynamicCounterID = @counterID)
      RAISERROR ('Delete not allowed, counter registered in metric.collections.dynamicCounterID', 16, 1)

    IF EXISTS(SELECT * FROM metric.collectionCounters WHERE counterID = @counterID)
      RAISERROR ('Delete not allowed, counter registered in metric.collectionCounters.counterID', 16, 1)

    BEGIN TRANSACTION

    DELETE FROM zmetric.columns WHERE counterID = @counterID

    DELETE FROM zmetric.counters WHERE counterID = @counterID

    COMMIT TRANSACTION
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0
      ROLLBACK TRANSACTION
    EXEC zsystem.CatchError 'metric.Counters_Delete'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON metric.Counters_Delete TO zzp_server
GO



IF OBJECT_ID('metric.Collections_Delete') IS NOT NULL
  DROP PROCEDURE metric.Collections_Delete
GO
CREATE PROCEDURE metric.Collections_Delete
  @collectionID  int
AS
  SET NOCOUNT ON

  BEGIN TRY
    DECLARE @cursor CURSOR

    IF @collectionID IS NULL
      RAISERROR ('@collectionID must be set', 16, 1)

    IF NOT EXISTS(SELECT * FROM metric.collections WHERE collectionID = @collectionID)
      RAISERROR ('Collection not found', 16, 1)

    DECLARE @dashboardID int, @collections varchar(max)

    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT TOP 10 dashboardID, collections FROM metric.dashboards ORDER BY dashboardID
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @dashboardID, @collections
    WHILE @@FETCH_STATUS = 0
    BEGIN
      IF EXISTS(SELECT * FROM zutil.IntListToTable(@collections) WHERE number = @collectionID)
        RAISERROR ('Delete not allowed, collection registered in metric.dashboards.collections (dashboardID = %d)', 16, 1, @dashboardID)

      FETCH NEXT FROM @cursor INTO @dashboardID, @collections
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    BEGIN TRANSACTION

    DELETE FROM metric.collectionCounters WHERE collectionID = @collectionID

    DELETE FROM metric.collections WHERE collectionID = @collectionID

    COMMIT TRANSACTION
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0
      ROLLBACK TRANSACTION
    IF CURSOR_STATUS('variable', '@cursor') > -1
      CLOSE @cursor
    IF CURSOR_STATUS('variable', '@cursor') = -1
      DEALLOCATE @cursor
    EXEC zsystem.CatchError 'metric.Collections_Delete'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON metric.Collections_Delete TO zzp_server
GO



IF OBJECT_ID('metric.UpdateLookupValue') IS NOT NULL
  DROP PROCEDURE metric.UpdateLookupValue
GO
CREATE PROCEDURE metric.UpdateLookupValue
  @lookupTableID  int,
  @lookupID       int,
  @lookupText     nvarchar(1000),
  @fullText       nvarchar(1000) = NULL
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @fullText IS NULL
    BEGIN
      IF NOT EXISTS(SELECT * FROM zsystem.lookupValues WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID AND lookupText = @lookupText)
      BEGIN
        UPDATE zsystem.lookupValues SET lookupText = @lookupText WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID
        IF @@ROWCOUNT = 0
          INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (@lookupTableID, @lookupID, @lookupText)
      END
    END
    ELSE
    BEGIN
      IF NOT EXISTS(SELECT * FROM zsystem.lookupValues WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID AND lookupText = @lookupText AND [fullText] = @fullText)
      BEGIN
        UPDATE zsystem.lookupValues SET lookupText = @lookupText, [fullText] = @fullText WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID
        IF @@ROWCOUNT = 0
          INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText, [fullText]) VALUES (@lookupTableID, @lookupID, @lookupText, @fullText)
      END
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'metric.UpdateLookupValue'
    RETURN -1
  END CATCH
GO



IF OBJECT_ID('metric.BeforeExecDataProcs') IS NOT NULL
  DROP PROCEDURE metric.BeforeExecDataProcs
GO
CREATE PROCEDURE metric.BeforeExecDataProcs
  @sourceType          varchar(20) = 'DB',
  @fromProcedureOrder  tinyint = 0,
  @toProcedureOrder    tinyint = 255
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  --IF @sourceType = 'DB' AND @fromProcedureOrder = 0 AND @toProcedureOrder = 200
  --BEGIN
  --  DECLARE @eventID int
  --  EXEC @eventID = zsystem.Events_TaskStarted 'metric.BeforeExecDataProcs', 'DB 0-200'

  --  EXEC metric.UpdateLookupTables

  --  EXEC zsystem.Events_TaskCompleted @eventID
  --END
GO



IF OBJECT_ID('metric.AfterExecDataProcs') IS NOT NULL
  DROP PROCEDURE metric.AfterExecDataProcs
GO
CREATE PROCEDURE metric.AfterExecDataProcs
  @sourceType          varchar(20) = 'DB',
  @fromProcedureOrder  tinyint = 0,
  @toProcedureOrder    tinyint = 255
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  --IF @sourceType = 'DB'
  --BEGIN
  --  DECLARE @eventID int

  --  IF @fromProcedureOrder = 0 AND @toProcedureOrder = 200
  --  BEGIN
  --    EXEC @eventID = zsystem.Events_TaskStarted 'metric.AfterExecDataProcs', 'DB 0-200', NULL, @fromProcedureOrder, @toProcedureOrder

  --    EXEC ...

  --    EXEC zsystem.Events_TaskCompleted @eventID, NULL, @fromProcedureOrder, @toProcedureOrder
  --  END
  --  ELSE IF @fromProcedureOrder = 201 AND @toProcedureOrder = 255
  --  BEGIN
  --    EXEC @eventID = zsystem.Events_TaskStarted 'metric.AfterExecDataProcs', 'DB 201-255', NULL, @fromProcedureOrder, @toProcedureOrder

  --    EXEC metric.Alerts_Check 1

  --    EXEC ...

  --    EXEC zsystem.Events_TaskCompleted @eventID, NULL, @fromProcedureOrder, @toProcedureOrder
  --  END
  --END
GO



IF OBJECT_ID('metric.ExecDataProcs') IS NOT NULL
  DROP PROCEDURE metric.ExecDataProcs
GO
CREATE PROCEDURE metric.ExecDataProcs
  @sourceType          varchar(20) = 'DB',
  @fromProcedureOrder  tinyint = 0,
  @toProcedureOrder    tinyint = 255
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  ---- Check if data processes should be executed by Metrics or Task manager
  --IF zsystem.Settings_Value('zmetric', 'ExecuteDataProcsInTaskmanager') != 1
  --BEGIN
  
    EXEC metric.BeforeExecDataProcs @sourceType, @fromProcedureOrder, @toProcedureOrder

    DECLARE @eventID int, @eventID2 int, @eventText nvarchar(max), @fixedText nvarchar(450)

    SET @fixedText = @sourceType
    IF NOT (@fromProcedureOrder = 0 AND @toProcedureOrder = 255)
      SET @fixedText = @fixedText + ' ' + CONVERT(nvarchar, @fromProcedureOrder) + '-' + CONVERT(nvarchar, @toProcedureOrder)
    EXEC @eventID = zsystem.Events_TaskStarted 'metric.ExecDataProcs', @fixedText, NULL, @fromProcedureOrder, @toProcedureOrder

    DECLARE @recipients varchar(max), @bodyHTML nvarchar(MAX) = '', 
            @counterOwners varchar(MAX) = '', @allRecipients varchar(MAX), @mailTitle varchar(MAX) 
    SET @recipients = zsystem.Settings_Value('Recipients', 'Admin - Proc errors')

    DECLARE @procedureName nvarchar(500)
    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT LTRIM(RTRIM(procedureName))
            FROM zmetric.counters
           WHERE sourceType = @sourceType AND hidden = 0 AND procedureName IS NOT NULL AND LTRIM(procedureName) != '' AND obsolete = 0
             AND procedureOrder BETWEEN @fromProcedureOrder AND @toProcedureOrder
             AND procedureName NOT IN (SELECT DISTINCT procedureName FROM zmetric.counters WHERE sourceType = @sourceType AND procedureName IS NOT NULL AND procedureOrder < @fromProcedureOrder)
           GROUP BY LTRIM(RTRIM(procedureName))
           ORDER BY MIN(procedureOrder), MIN(counterID)
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @procedureName
    WHILE @@FETCH_STATUS = 0
    BEGIN
      -- Procedure started event
      EXEC @eventID2 = zsystem.Events_TaskStarted @procedureName, @fixedText, NULL, @fromProcedureOrder, @toProcedureOrder, @parentID=@eventID

      -- Procedure execute 
      BEGIN TRY
        EXEC @procedureName
      END TRY
      BEGIN CATCH
        -- Procedure ERROR event
        SET @eventText = ERROR_MESSAGE()
        EXEC zsystem.Events_TaskError @eventID2, @eventText
        -- Find counter owners
        ;WITH distinctOwners AS (
          SELECT DISTINCT userName 
            FROM zmetric.counters 
           WHERE procedureName = @procedureName
        )
        SELECT @counterOwners = @counterOwners + ';' + userName + '@ccpgames.com' FROM distinctOwners
        SET @allRecipients = @recipients + @counterOwners
        SET @mailTitle = 'DATA PROC ERROR: ' + @procedureName
        -- Procedure ERROR mail
        DECLARE @objectName nvarchar(256)
        SET @objectName = 'metric.ExecDataProcs: ' + @procedureName
        SET @bodyHTML = @bodyHTML + N'<font size=4 color=navy><b>' + @procedureName + '</b></font><br>'
        SET @bodyHTML = @bodyHTML + N'<font color=red>' + ERROR_MESSAGE() + '</font><br><br>'
        -- Send ERROR mail
        IF @allRecipients != '' AND @bodyHTML != ''
          EXEC msdb.dbo.sp_send_dbmail NULL, @allRecipients, NULL, NULL, @mailTitle, @bodyHTML, 'HTML', @from_address='evemetrics@ccpgames.com'
        -- Reset variables
        SET @counterOwners = ''
        SET @allRecipients = ''

        EXEC zsystem.CatchError @objectName
      END CATCH

      -- Procedure completed event
      EXEC zsystem.Events_TaskCompleted @eventID2, NULL, @fromProcedureOrder, @toProcedureOrder

      FETCH NEXT FROM @cursor INTO @procedureName
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- Total completed event
    EXEC zsystem.Events_TaskCompleted @eventID, NULL, @fromProcedureOrder, @toProcedureOrder

    EXEC metric.AfterExecDataProcs @sourceType, @fromProcedureOrder, @toProcedureOrder

  --END
GO



IF OBJECT_ID('metric.PageViews_Insert') IS NOT NULL
  DROP PROCEDURE metric.PageViews_Insert
GO
CREATE PROCEDURE metric.PageViews_Insert
  @method         varchar(50),
  @counterID      smallint,
  @collectionID   int,
  @dashboardID    int,
  @contextNumber  int,
  @url            varchar(512),
  @userName       varchar(50),
  @hostName       varchar(50),
  @ipNumber       varchar(50),
  @agent          varchar(512)
AS
  SET NOCOUNT ON

  INSERT INTO pageViews (method, counterID, collectionID, dashboardID, contextNumber, url, userName, hostName, ipNumber, agent)
       VALUES (@method, @counterID, @collectionID, @dashboardID, @contextNumber, @url, @userName, @hostName, @ipNumber, @agent)
GO




IF OBJECT_ID('metric.CopyCounter') IS NOT NULL
  DROP PROCEDURE metric.CopyCounter
GO
CREATE PROCEDURE metric.CopyCounter
  @counterIdentifier  varchar(500)
AS
  SET NOCOUNT ON

  BEGIN TRY
    DECLARE @counterID                     smallint,
            @counterName                   nvarchar(200),
            @groupName                     nvarchar(200),
            @description                   nvarchar(max),
            @subjectLookupTableIdentifier  varchar(500),
            @keyLookupTableIDIdentifier    varchar(500),
            @source                        nvarchar(200),
            @subjectID                     nvarchar(200),
            @keyID                         nvarchar(200),
            @absoluteValue                 bit,
            @shortName                     nvarchar(50),
            @order                         smallint,
            @procedureName                 nvarchar(500),
            @procedureOrder                tinyint,
            @parentCounterID               smallint,
            @parentCounterIdentifier       varchar(500),
            @baseCounterID                 smallint,
            @counterType                   char(1),
            @obsolete                      bit,
            @hidden                        bit,
            @published                     bit,
            @sourceType                    varchar(20),
            @units                         varchar(20),
            @counterTable                  nvarchar(256) 

     SELECT @counterID = counterID,
            @counterName = counterName,
            @groupName = groupName,
            @description = [description],
            @subjectLookupTableIdentifier = subjectLookupTableIdentifier,
            @keyLookupTableIDIdentifier = keyLookupTableIdentifier,
            @source = [source],
            @subjectID = subjectID,
            @keyID = keyID,
            @absoluteValue = absoluteValue,
            @shortName = shortName,
            @order = [order],
            @procedureName = procedureName,
            @procedureOrder = procedureOrder,
            @parentCounterID = parentCounterID,
            @baseCounterID = baseCounterID,
            @counterType = counterType,
            @obsolete = obsolete,
            @hidden = hidden,
            @published = published,
            @sourceType = sourceType,
            @units = units,
            @counterTable = counterTable
       FROM zmetric.countersEx
      WHERE counterIdentifier = @counterIdentifier
    IF @counterID IS NULL
      RAISERROR ('Counter not found', 16, 1)

    IF @parentCounterID IS NOT NULL
      SELECT @parentCounterIdentifier = counterIdentifier FROM zmetric.counters WHERE counterID = @parentCounterID

    PRINT 'IF EXISTS(SELECT * FROM zmetric.counters WHERE counterIdentifier = ''' + @counterIdentifier + ''')'
    PRINT '  PRINT ''Counter already exists !!!'''
    PRINT 'ELSE'
    PRINT 'BEGIN'
    PRINT '  DECLARE @counterID smallint'
    PRINT '  SELECT @counterID = ISNULL(MAX(counterID) + 1, 1) FROM zmetric.counters WHERE counterID < 30000'
    PRINT ''
    PRINT '  DECLARE @groupID smallint'
    IF @groupName IS NOT NULL
      PRINT '  SELECT @groupID = groupID FROM zmetric.groups WHERE groupName = ''' + @groupName + ''''
    PRINT ''
    PRINT '  DECLARE @subjectLookupTableID int'
    IF @subjectLookupTableIdentifier IS NOT NULL
      PRINT '  SELECT @subjectLookupTableID = lookupTableID FROM zsystem.lookupTables WHERE lookupTableIdentifier = ''' + @subjectLookupTableIdentifier + ''''
    PRINT ''
    PRINT '  DECLARE @keyLookupTableID int'
    IF @keyLookupTableIDIdentifier IS NOT NULL
      PRINT '  SELECT @keyLookupTableID = lookupTableID FROM zsystem.lookupTables WHERE lookupTableIdentifier = ''' + @keyLookupTableIDIdentifier + ''''
    PRINT ''
    PRINT '  DECLARE @parentCounterID smallint'
    IF @parentCounterIdentifier IS NOT NULL
      PRINT '  SELECT @parentCounterID = counterID FROM zmetric.counters WHERE counterIdentifier = ''' + @parentCounterIdentifier + ''''
    PRINT ''
    PRINT '  INSERT INTO zmetric.counters'
    PRINT '              (counterID, groupID, counterName, [description], subjectLookupTableID, keyLookupTableID, [source], subjectID, keyID, absoluteValue, shortName, [order],'
    PRINT '               procedureName, procedureOrder, parentCounterID, baseCounterID, counterType, obsolete, counterIdentifier, hidden, published, sourceType, units, counterTable)'
    PRINT '       VALUES (@counterID, @groupID, '
          + '''' + @counterName + ''', '
          + CASE WHEN @description IS NULL THEN 'NULL' ELSE '''' + @description + '''' END + ', '
          + '@subjectLookupTableID, '
          + '@keyLookupTableID, '
          + CASE WHEN @source IS NULL THEN 'NULL' ELSE '''' + @source + '''' END + ', '
          + CASE WHEN @subjectID IS NULL THEN 'NULL' ELSE '''' + @subjectID + '''' END + ', '
          + CASE WHEN @keyID IS NULL THEN 'NULL' ELSE '''' + @keyID + '''' END + ', '
          + CONVERT(varchar, @absoluteValue) + ', '
          + CASE WHEN @shortName IS NULL THEN 'NULL' ELSE '''' + @shortName + '''' END + ', '
          + CONVERT(varchar, @order) + ', '
          + CASE WHEN @procedureName IS NULL THEN 'NULL' ELSE '''' + @procedureName + '''' END + ', '
          + CONVERT(varchar, @procedureOrder) + ', '
          + '@parentCounterID, '
          + CASE WHEN @baseCounterID IS NULL THEN 'NULL' ELSE '''' + CONVERT(varchar, @baseCounterID) + '''' END + ', '
          + '''' + @counterType + ''', '
          + CONVERT(varchar, @obsolete) + ', '
          + '''' + @counterIdentifier + ''', '
          + CONVERT(varchar, @hidden) + ', '
          + CONVERT(varchar, @published) + ', '
          + CASE WHEN @sourceType IS NULL THEN 'NULL' ELSE '''' + @sourceType + '''' END + ', '
          + CASE WHEN @units IS NULL THEN 'NULL' ELSE '''' + @units + '''' END + ', '
          + CASE WHEN @counterTable IS NULL THEN 'NULL' ELSE '''' + @counterTable + '''' END + ')'

      DECLARE @columnID tinyint, @columnName nvarchar(200)
      DECLARE @cursor CURSOR
      SET @cursor = CURSOR LOCAL STATIC READ_ONLY --FAST_FORWARD
        FOR SELECT columnID, columnName, [description], [order], units FROM zmetric.columns WHERE counterID = @counterID ORDER BY columnID
      OPEN @cursor
      FETCH NEXT FROM @cursor INTO @columnID, @columnName, @description, @order, @units
      WHILE @@FETCH_STATUS = 0
      BEGIN
        PRINT ''
        PRINT '  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description], [order], units)'
        PRINT '       VALUES (@counterID, '
          + CONVERT(varchar, @columnID) + ', '
          + '''' + @columnName + ''', '
          + CASE WHEN @description IS NULL THEN 'NULL' ELSE '''' + @description + '''' END + ', '
          + CONVERT(varchar, @order) + ', '
          + CASE WHEN @units IS NULL THEN 'NULL' ELSE '''' + @units + '''' END + ')'

        FETCH NEXT FROM @cursor INTO @columnID, @columnName, @description, @order, @units
      END
      CLOSE @cursor
      DEALLOCATE @cursor

    PRINT 'END'
    PRINT 'GO'
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'metric.CopyCounter'
    RETURN -1
  END CATCH
GO




IF OBJECT_ID('metric.CopyLookupTable') IS NOT NULL
  DROP PROCEDURE metric.CopyLookupTable
GO
CREATE PROCEDURE metric.CopyLookupTable
  @lookupTableIdentifier  varchar(500)
AS
  SET NOCOUNT ON

  BEGIN TRY
    DECLARE @lookupTableName       nvarchar(200),
            @description           nvarchar(max),
            @schemaID              int,
            @tableID               int,
            @source                nvarchar(200),
            @lookupID              nvarchar(200),
            @parentID              nvarchar(200),
            @parentLookupTableID   int,
            @link                  nvarchar(500),
            @hidden                bit,
            @obsolete              bit,
            @sourceForID           varchar(20),
            @label                 nvarchar(200)

    SELECT @lookupTableName = lookupTableName,
           @description = [description],
           @schemaID = schemaID,
           @tableID = tableID,
           @source = [source],
           @lookupID = lookupID,
           @parentID = parentID,
           @parentLookupTableID = parentLookupTableID,
           @link = link,
           @hidden = hidden,
           @obsolete = obsolete,
           @sourceForID = sourceForID,
           @label = label
      FROM zsystem.lookupTables
     WHERE lookupTableIdentifier = @lookupTableIdentifier

    IF @lookupTableName IS NULL
      RAISERROR ('Lookup table not found', 16, 1)

    PRINT 'IF EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableIdentifier = ''' + @lookupTableIdentifier + ''')'
    PRINT '  PRINT ''Lookup table already exists !!!'''
    PRINT 'ELSE'
    PRINT 'BEGIN'
    PRINT '  DECLARE @lookupTableID int'
    PRINT '  SELECT @lookupTableID = ISNULL(MAX(lookupTableID) + 1, 1) FROM zsystem.lookupTables WHERE lookupTableID < 2000000000'
    PRINT ''
    PRINT '  INSERT INTO zsystem.lookupTables'
    PRINT '              (lookupTableID, lookupTableName, [description], schemaID, tableID, [source], lookupID, parentID, parentLookupTableID, link, lookupTableIdentifier, hidden, obsolete, sourceForID, label)'
    PRINT '       VALUES (@lookupTableID, '
          + '''' + @lookupTableName + ''', '
          + CASE WHEN @description IS NULL THEN 'NULL' ELSE '''' + @description + '''' END + ', '
          + CASE WHEN @schemaID IS NULL THEN 'NULL' ELSE CONVERT(varchar, @schemaID) END + ', '
          + CASE WHEN @tableID IS NULL THEN 'NULL' ELSE CONVERT(varchar, @tableID) END + ', '
          + CASE WHEN @source IS NULL THEN 'NULL' ELSE '''' + @source + '''' END + ', '
          + CASE WHEN @lookupID IS NULL THEN 'NULL' ELSE '''' + @lookupID + '''' END + ', '
          + CASE WHEN @parentID IS NULL THEN 'NULL' ELSE '''' + @parentID + '''' END + ', '
          + CASE WHEN @parentLookupTableID IS NULL THEN 'NULL' ELSE CONVERT(varchar, @parentLookupTableID) END + ', '
          + CASE WHEN @link IS NULL THEN 'NULL' ELSE '''' + @link + '''' END + ', '
          + '''' + @lookupTableIdentifier + ''', '
          + CONVERT(varchar, @hidden) + ', '
          + CONVERT(varchar, @obsolete) + ', '
          + CASE WHEN @sourceForID IS NULL THEN 'NULL' ELSE '''' + @sourceForID + '''' END + ', '
          + CASE WHEN @label IS NULL THEN 'NULL' ELSE '''' + @label + '''' END + ')'
    PRINT 'END'
    PRINT 'GO'
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'metric.CopyCounter'
    RETURN -1
  END CATCH
GO
