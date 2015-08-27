# -*- coding: utf-8 -*-
# this file is released under public domain and you can use without limitations
import types, locale, datetime, collections, pyodbc, json
import functools
import time
import sys
from operator import itemgetter
import subprocess, os
import socket

try:
    import ldap # http://pypi.python.org/pypi/python-ldap/
except ImportError:
    print "Could not import LDAP. Download from http://pypi.python.org/pypi/python-ldap/"

class WriteNullBuffer:
    def __init__(self):
        pass
    def write(self, text):
        pass
    def flush(self):
        pass
    def fileno(self):
        return 3

def Login():
    userName = ""
    error = ""
    if request.vars.username:
        userName = request.vars.username.split("@")[0]
        password = request.vars.password
        user = None
        if userName and (password):
            user = DoLogin(userName, password)
        if user is None:
            error = "<span style=\"font-weight:bold;\">You could not be logged on.</span><br>Please make sure that your user name and password are correct, and then try again."
        else:
            redirect(request.vars.redirect or "/")
    else:
        userName = GetCookie("userName")
    return {
        "userName": userName,
        "error"   : error,
        "redirect" : request.vars.redirect
        }

def DoLogin(userName, password=None):
    user = [userName, userName, []]
    if user is not None:
        session.userName = user[0]
        session.fullName = user[1]
        session.groups   = user[2]
        session.emailAddress = user[0] + "@ccpgames.com"
        session.teamName = GetTeamForUser(user[0])
        if session.teamName:
            session.teamName = "Team " + session.teamName
        SetCookie("userName", session.userName)
    return user


def Logout():
    session.clear()
    SetCookie("userName", "")
    redirect("/")


def GetLDAP():
    DN = "ccp\LDAP_SERVICE_USER"
    password = "CHANGEME"
    username = "LDAP_SERVICE_USER"
    l = ldap.initialize("ldap://ccp.ad.local")
    l.set_option(ldap.OPT_REFERRALS, 0)
    l.protocol_version = 3
    con = l.simple_bind_s(DN, password)
    return l

def FindRecipientInAD(email):
    l = GetLDAP()
    Base = "dc=ccp,dc=ad,dc=local"
    Scope = ldap.SCOPE_SUBTREE
    Filter = "(&(mail=%s))" % (email)
    attrs = ["mailNickname", "displayName", "memberOf", "objectClass"]
    l = GetLDAP()
    r = l.search(Base, Scope, Filter, attrs)
    resultType, ADUsers = l.result(r, 60)
    if not ADUsers[0][0]:
        return None
    usr = ADUsers[0][1]
    isMailingList = 0
    for c in usr["objectClass"]:
        if c == "group":
            isMailingList = 1
            break
    displayName = usr["displayName"][0]
    displayName = displayName.decode("UTF-8")
    return displayName, isMailingList

def FindGroupsRecursive(l, filt):
    Base = "dc=ccp,dc=ad,dc=local"
    Scope = ldap.SCOPE_SUBTREE
    attrs = ["mailNickname", "displayName", "memberOf", "objectClass"]
    r = l.search(Base, Scope, filt, attrs)
    resultType, results = l.result(r, 60)
    if not results[0][0]:
        return []
    entry = results[0][1]
    groups = []
    if "memberOf" in entry:
        for e in entry["memberOf"]:
            groupName = e.split(",")[0].replace("CN=", "")
            groups.append(groupName)
            groups.extend(FindGroupsRecursive(l, "(&(cn=%s))" % groupName))
    return sorted(set(groups))

def AuthenticateAD(userName, password):
    l = ldap.initialize("ldap://ccp.ad.local")
    l.set_option(ldap.OPT_REFERRALS, 0)
    l.protocol_version = 3
    if password:
        try:
            con = l.simple_bind_s(userName + "@ccp.ad.local", password)
        except ldap.INVALID_CREDENTIALS:
            return None

    Base = "dc=ccp,dc=ad,dc=local"
    Scope = ldap.SCOPE_SUBTREE
    Filter = "(&(objectClass=user)(mailNickname=%s))" % (userName)
    attrs = ["mailNickname", "uSNCreated", "displayName", "memberOf"]
    l = GetLDAP()
    r = l.search(Base, Scope, Filter, attrs)
    resultType, ADUsers = l.result(r,60)
    if not ADUsers[0][0]:
        return None
    user = ADUsers[0][1]
    groups = []
    t = time.time()
    f = "(&(mailNickname=%s))" % userName
    groups = FindGroupsRecursive(l, f)
    print "Found %s groups for %s in %.4f" % (len(groups), userName, time.time()-t)
    return user["mailNickname"][0], user["displayName"][0], groups


def TestLdap():
    # http://pypi.python.org/pypi/python-ldap/
    txt = ""


    name = request.vars.name or ""
    Base = "dc=ccp,dc=ad,dc=local"
    Scope = ldap.SCOPE_SUBTREE
    Filter = "(&(objectClass=user)(mailNickname=%s*))" % (name)
    attrs = ["displayname", "mail", "memberof", "name", "UserAccountControl", "thumbnailPhoto"]
    attrs = ["displayname", "mail", "url", "mailNickname", "uSNCreated"]
    attrs = ["mailNickname", "uSNCreated", "displayName"]
    #attrs = ["*"]

    r = l.search(Base, Scope, Filter, attrs)
    Type,user = l.result(r,60)
    allUsers = {}
    for u in user:
        lst = []
        try:
            for a in u[1].values():
                lst.append(a[0])
        except:
            continue
        uid = int(lst[1])
        if uid in allUsers:
            print "FUCK!", uid, lst[0], allUsers[uid]
        else:
            print "new guy", lst[0]
        allUsers[uid] = lst[0]
    Name,attrs = user[0]
    txt += "<img src=\"http://myccp/User Photos/Profile Pictures/ccp_%s_LThumb.jpg\">" % name
    if type(attrs) == types.DictType:
        for k, v in attrs.iteritems():
            if "url" in k and 0:
                txt += "<img src=\"%s\"><br>" % v[0]
            else:
                txt += "%s > %s<br><Br>" % (k, v[0][:128]) 
    return txt

def ProcessAccessRules(contentType, contentID, ownerUserName=None, subContent=0, embedded=0):
    if request.vars.secret:
        session.secret = request.vars.secret
    ownerUserName = (ownerUserName or "").lower()

    access = IsRestricted(contentType, contentID)

    if access == ACCESS_GRANTED:
        return

    if access == ACCESS_OPEN:
        #print "No access restrictions for %s : %s" % (contentType, contentID)
        return

    try:
        ownerUserName = GetAccessRules()[(contentType, contentID)][0].ownerUserName
    except:
        ownerUserName = "Unknown"
    if ownerUserName and ownerUserName == (session.userName or "").lower():
        print "I own this content"
        return

    if access == ACCESS_DENIED_LOGGEDOUT:
        redirect(URL("Login?redirect=%s" % GetFullUrl()))

    em = ""
    if embedded:
        em = "Embedded"
    redirect("%sAccessDenied?contentType=%s&contentID=%s&ownerUserName=%s&subContent=%s&redirect=%s" % (em, contentType, contentID, ownerUserName, int(subContent), GetFullUrl()))


def EmbeddedAccessDenied():
    return AccessDenied()

def AccessDenied():
    contentType = request.vars.contentType
    contentID = int(request.vars.contentID)
    ownerUserName = GetContentOwner(contentType, contentID)
    redirectUrl = request.vars.redirect
    return {
        "contentType" : contentType,
        "contentID" : contentID,
        "ownerUserName" : ownerUserName,
        "redirectUrl" : redirectUrl,
    }

def GetMemoryUsage():
    from wmi import WMI
    w = WMI(".")
    ret = w.query("SELECT WorkingSet FROM Win32_PerfRawData_PerfProc_Process WHERE IDProcess = %s" % os.getpid())[0]
    KB = 1024
    return int(ret.WorkingSet)/KB


def GetSystemMessage():
    sql = "SELECT [value] FROM zsystem.settings WHERE [group] = 'metrics' and [key] = 'evemetricsSystemMessage'"
    curr = MakeCursor("ebs_METRICS")
    curr.execute(sql)
    rows = curr.fetchall()
    if rows and rows[0][0]:
        return rows[0][0]
    return None

def FuncTime(action, *args, **kwargs):
    @functools.wraps(action)
    def wrapper(*args, **kwargs):
        response.systemMessage = cache.ram("SystemMessage", GetSystemMessage, 0) # cache for 30 minutes

        response.procquery = []
        response.mainquery = []
        response.query = []
        if not session.userName:
            userName = GetCookie("userName")
            if userName:
                DoLogin(userName)
        if request.vars.message:
            response.flash = request.vars.message
        #f = open("C:\\web2pylogs\logs.txt", "a+")
        #f.write("%s\t%s\t%s\t%s\n" % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), request.env.remote_addr, action, dict(request.vars)))
        #f.close()
        startTime = time.time()
        ret = action(*args, **kwargs)
        try:
            LogPageLoad()
        except:
            pass

        response.buildtime = "%.3f" % (time.time()-startTime)
        t = "unknown"
        t = datetime.datetime.now()
        logTimes = []
        #memoryUsageAfter = GetMemoryUsage()
        #print "%s\t%s\t%s\t%s\t%s" % (GetFullUrl(), session.userName, memoryUsageBefore, memoryUsageAfter, memoryUsageAfter - memoryUsageBefore)

        #response.nextlogs = t
        return ret
    return wrapper

def LogPageLoad():
    userName = session.userName
    ip = hostname = None
    if session.hostName is None:
        hostname = ""
        try:
            ip = request.env.remote_addr
            hostname = socket.gethostbyaddr(ip)[0]
        except:
            pass
        session.hostName = hostname
    sql = """EXEC zsystem.Events_Insert 1, @eventText='%s,%s,%s,%s'""" % (userName, session.hostName, ip, GetFullUrl())

    VIEWTYPE_REPORT     = "Report"
    VIEWTYPE_COLLECTION = "Collection"
    VIEWTYPE_GRAPH      = "Graph"
    VIEWTYPE_DASHBOARD  = "Dashboard"
    VIEWTYPE_OTHER      = "Other"
    url = GetFullUrl()
    method = url.split("/")[1].split("?")[0]
    viewType = VIEWTYPE_OTHER
    counterID = "NULL"
    collectionID = "NULL"
    dashboardID = "NULL"
    n = "NULL"
    if method.lower() == "report":
        try:
            counterID = int(request.vars.counterID or 0)
        except:
            counterID = 0
    if method.lower() == "dashboard":
        dashboardID = int(request.vars.dashboardID or 0)
    elif method.lower() == "counters":
        if request.vars.collectionID:
            collectionID = int(request.vars.collectionID or 0)
        elif request.vars.graph:
            g = request.vars.graph
            n = 1
            if type(g) == types.ListType:
                n = len(g)
                g = g[0]
            lst = g.split("_")
            counterID = int(lst[0])
            if int(lst[-1]) < 0:
                n = -int(lst[-1])
        elif request.vars.counterID:
            counterID = int(request.vars.counterID)
        n = (response.numCharts or 0)

    elif method.lower() == "viewpagelookups":
        return

    agent = request.env.http_user_agent[:512]
    url = url[:512]
    sql = """EXEC metric.PageViews_Insert '%s', %s, %s, %s, %s, '%s', '%s', '%s', '%s', '%s'""" % (method, counterID, collectionID, dashboardID, n, GetFullUrl()[:512], userName or "NULL", session.hostName or "NULL", ip or "NULL", agent or "NULL")

    dbmetrics.executesql(sql)

def JQueryUI():
    return {"txt": "hello"}

@FuncTime
def AccessRules():
    LoggedIn()
    contentType = request.vars.contentType
    contentID = int(request.vars.contentID)
    rules = DoGetAccessRules().get((contentType, contentID), [])
    ownerUserName = ""
    contentTitle = ""
    contentUrl = ""
    if contentType == "COUNTER":
        counter = GetCounterInfo(contentID)
        ownerUserName = counter.userName
        contentTitle = counter.counterName
        contentUrl = "Report?counterID=%d" % contentID
    elif contentType == "COLLECTION":
        collection = GetCollection(contentID)
        ownerUserName = collection.userName
        contentTitle = collection.collectionName
        contentUrl = "Counters?collectionID=%d" % contentID
    elif contentType == "DASHBOARD":
        dashboard = GetDashboardRow(contentID)
        ownerUserName = dashboard.userName
        contentTitle = dashboard.dashboardName
        contentUrl = "Dashboard?dashboardID=%d" % contentID
    elif contentType == "DIGEST":
        digest = GetDigestRow(contentID)
        ownerUserName = digest.userName
        contentTitle = digest.digestName
        contentUrl = "ViewDigest?digestID=%d" % contentID   
    else:
        raise Exception("Unsupported contentType")
    isOwner = (ownerUserName == session.userName)
    return {
        "contentType"   : contentType,
        "contentID"     : contentID,
        "rules"         : rules,
        "ownerUserName" : ownerUserName,
        "isOwner"       : isOwner,
        "contentTitle"  : contentTitle,
        "contentUrl"    : contentUrl,
    }

def DeleteAccessRule():
    LoggedIn()
    contentType = request.vars.contentType
    contentID = int(request.vars.contentID)
    accessRuleID = int(request.vars.accessRuleID)
    rules = DoGetAccessRules().get((contentType, contentID), [])
    for r in rules:
        if r.accessRuleID == accessRuleID:
            if r.ownerUserName != session.userName and 0:
                session.flash = "Only the content owner, %s can change the access rules" % r.ownerUserName
                break
            else:
                sql = "DELETE FROM metric.accessRules WHERE accessRuleID = %d" % accessRuleID
                dbmetrics.executesql(sql)
                session.flash = "Access has been revoked"
                break
    else:
        session.flash = "Rule not found"
    cache.ram("accessRules", None, 0)
    redirect(request.env.http_referer)

def GetContentOwner(contentType, contentID):
    name = ""
    if contentType == "COUNTER":
        counter = GetCounterInfo(contentID)
        return counter.userName
    elif contentType == "COLLECTION":
        counter = GetCollection(contentID)
        return counter.userName
    elif contentType == "DASHBOARD":
        dashboard = GetDashboardRow(contentID)
        return dashboard.userName
    elif contentType == "DIGEST":
        digest = GetDigestRow(contentID)
        return digest.userName
    else:
        return "Unknown"

def GetDashboardRow(dashboardID):
    sql = "SELECT * FROM metric.dashboards WHERE dashboardID = %d" % dashboardID
    return dbmetrics.executesql(sql)[0]

def AddAccessRule():
    LoggedIn()
    cache.ram("accessRules", None, 0)
    contentType = request.vars.contentType
    contentID = int(request.vars.contentID)
    ownerUserName = GetContentOwner(contentType, contentID)
    if ownerUserName != session.userName:
        session.flash = "Only the owner of this page, %s can change the access rules" % ownerUserName
        redirect(request.env.http_referer)
    emails = request.vars.emails.split(",")
    emails.append(session.emailAddress)
    userName = session.userName

    existingEmails = set()
    emailsToAdd = set()
    badEmails = set()

    sql = "SELECT emailAddress FROM metric.accessRules WHERE contentType = '%s' AND contentID = '%s'" % (contentType, contentID)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        existingEmails.add(r.emailAddress.lower())

    for email in emails:
        email = email.lower().strip()
        if not email:
            continue
        if "@" not in email:
            email += "@ccpgames.com"

        recipient = FindRecipientInAD(email)
        if not recipient:
            badEmails.add(email)
            continue
        fullName = recipient[0]
        isMailingList = recipient[1]

        if email in existingEmails:
            continue

        emailsToAdd.add((email, isMailingList, fullName))

    for email, isMailingList, fullName in emailsToAdd:
        sql = "INSERT INTO metric.accessRules (contentType, contentID, emailAddress, fullName, createdByUserName, mailingList) VALUES ('%s', %d, '%s', '%s', '%s', %d)" % (contentType, contentID, email, fullName, userName, isMailingList)
        dbmetrics.executesql(sql)

    if badEmails:
        session.flash = "The following emails were not found in Active Directory: %s" % (",".join(badEmails))
    redirect(request.env.http_referer)


#
# Markers
#

def GetMarkers(typeID=None):

    typeConstraint = ""
    if typeID:
        typeConstraint = "m.typeID = %s AND" % typeID

    sql = """
        SELECT m.markerID, m.userNameCreated, m.dateTimeCreated, m.userNameEdited, m.dateTimeEdited, m.title, m.dateTime, m.url, TYPE_TITLE = t.title, CATEGORY_TITLE = c.title, m.typeID, c.categoryID, m.important
          FROM markers m
            LEFT JOIN markerTypes t ON t.markerTypeID = m.typeID
              LEFT JOIN markerTypeCategories c ON c.categoryID = m.categoryID
        WHERE %s m.deleted = 0
        ORDER BY m.dateTime DESC
    """ % typeConstraint
    LogQuery(sql)
    rows = cache.ram("markers_%s" % typeID, lambda:dbmetrics.executesql(sql), CACHE_TIME_FOREVER)
    #rows = dbmetrics.executesql(sql)
    return rows

def GetDashboards():
    sql = "SELECT dashboardID=dashboardID, dashboardName, collections FROM metric.dashboards ORDER BY dashboardID ASC"
    rows = cache.ram("alldashboards", lambda:dbmetrics.executesql(sql), CACHE_TIME_FOREVER)
    allDashboards = GetDictFromRowset(rows)
    return allDashboards

def GetMarkersByCategory(categoryID):
    sql = """
        SELECT m.markerID, m.userNameCreated, m.dateTimeCreated, m.userNameEdited, m.dateTimeEdited, m.title, m.dateTime, m.url, TYPE_TITLE = t.title, CATEGORY_TITLE = c.title, m.typeID, c.categoryID, m.important
          FROM markers m
            LEFT JOIN markerTypes t ON t.markerTypeID = m.typeID
              LEFT JOIN markerTypeCategories c ON c.categoryID = m.categoryID
        WHERE m.categoryID = %d AND m.deleted = 0
        ORDER BY m.dateTime DESC
    """ % int(categoryID)
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    return rows

def GetMarkersForGraph(annotations):
    if annotations > 0:
        return GetMarkersByCategory(annotations)
    else:
        pers = ""
        cond = "(m.important <> 0)"
        if annotations == -2:
            pers = " OR (t.productID = 5 AND t.title LIKE '%s')" % session.userName
            cond = "(m.important <> 0%s)" % pers
        elif annotations == -3:
            cond = "(t.productID = 5 AND t.title LIKE '%s')" % session.userName
        sql = """
            SELECT m.markerID, m.userNameCreated, m.dateTimeCreated, m.userNameEdited, m.dateTimeEdited, m.title, m.dateTime, m.url, TYPE_TITLE = t.title, CATEGORY_TITLE = c.title, m.typeID, c.categoryID, m.important
              FROM markers m
                LEFT JOIN markerTypes t ON t.markerTypeID = m.typeID
                  LEFT JOIN markerTypeCategories c ON c.categoryID = m.categoryID
            WHERE %s AND m.deleted = 0
            ORDER BY m.dateTime DESC
        """ % cond
        LogQuery(sql)
        rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME_FOREVER)
        #rows = dbmetrics.executesql(sql)
        return rows

def GetMarker(markerID):
    sql = """
        SELECT m.markerID, m.userNameCreated, m.dateTimeCreated, m.userNameEdited, m.dateTimeEdited, m.title, m.dateTime, m.url, 
               TYPE_TITLE = t.title, CATEGORY_TITLE = c.title, m.description, m.typeID, c.categoryID, t.includeTime, m.important
          FROM markers m
            LEFT JOIN markerTypes t ON t.markerTypeID = m.typeID
              LEFT JOIN markerTypeCategories c ON c.categoryID = m.categoryID
        WHERE m.markerID = %s
        ORDER BY m.dateTime DESC
    """ % markerID
    rows = dbmetrics.executesql(sql)

    sql = """
        SELECT * FROM markerColumnValues v
          LEFT JOIN markerTypeColumns c ON c.markerColumnID = v.markerColumnID
         WHERE markerID = %s
         ORDER BY title ASC
    """ % markerID
    customRows = dbmetrics.executesql(sql)

    marker = KeyVal(marker=rows[0], customFields=customRows)

    return marker


def GetMarkerTypeName(typeID):
    if not typeID:
        return ""

    sql = "SELECT TOP 1 title FROM markerTypes WHERE markerTypeID = %d" % int(typeID)
    rows = dbmetrics.executesql(sql)
    ret = ""
    if rows:
        ret = rows[0].title
    return ret


def GetDictFromRowset(rows):
    ret = collections.OrderedDict()
    for r in rows:
        ret[r[0]] = r
    return ret


def GetMarkerTypes():
    sql = """SELECT * FROM markerTypes ORDER BY title ASC"""
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    return GetDictFromRowset(rows)


def GetMarkerCategoriesForType(typeID):
    sql = """SELECT * FROM markerTypeCategories WHERE markerTypeID = %s ORDER BY title ASC""" % typeID
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    return GetDictFromRowset(rows)

def GetMarkersFromRequest():
    typeConstraint = ""
    catConstraint = ""
    if request.vars.typeID:
        txt = ""
        typeIDs = request.vars.typeID
        if type(typeIDs) != types.ListType:
            typeIDs = [typeIDs]
        for t in typeIDs:
            txt += "'%s', " % int(t)
        if txt:
            txt = txt[:-2]
            typeConstraint = " m.typeID IN (%s) AND " % txt
    if request.vars.categoryID:
        txt = ""
        categoryIDs = request.vars.categoryID
        if type(categoryIDs) != types.ListType:
            categoryIDs = [categoryIDs]
        for t in categoryIDs:
            txt += "'%s', " % int(t)
        if txt:
            txt = txt[:-2]
            catConstraint = " m.categoryID IN (%s) AND " % txt
    sql = """
        SELECT m.markerID, m.userNameCreated, m.dateTimeCreated, m.userNameEdited, m.dateTimeEdited, m.title, m.dateTime, m.url, TYPE_TITLE = t.title, CATEGORY_TITLE = c.title, m.typeID, c.categoryID, m.important
          FROM markers m
            LEFT JOIN markerTypes t ON t.markerTypeID = m.typeID
              LEFT JOIN markerTypeCategories c ON c.categoryID = m.categoryID
        WHERE %s %s m.deleted = 0
        ORDER BY m.dateTime DESC
    """ % (typeConstraint, catConstraint)

    LogQuery(sql)
    rows = dbmetrics.executesql(sql, as_dict=True) # return as a dict so that we can enumerate the columns
    return rows


def MarkersJson():
    lst = []
    rows = GetMarkersFromRequest()
    for r in rows:
        lst.append(r)
    return response.json(lst)


def GetMarkerTypeForPersonal(typeID, create=False):
    sql = ""
    if typeID == -1:
        sql = "SELECT markerTypeID FROM markerTypes WHERE productID = 5 AND title = '%s'" % session.userName
    elif typeID == -2:
        sql = "SELECT markerTypeID FROM markerTypes WHERE productID = 6 AND title = '%s'" % session.teamName
    rows = dbmetrics.executesql(sql)
    if not rows:
        if create and session.userName:
            if typeID == -1:
                sql = "INSERT INTO markerTypes (productID, title, private) VALUES (5, '%s', 1)" % session.userName
                dbmetrics.executesql(sql)
                return GetMarkerTypeForPersonal(typeID)
        return None
    return rows[0].markerTypeID

@FuncTime
def Markers():
    if request.vars.format == "json":
        return MarkersJson()
    allMarkers = GetMarkersFromRequest()

    markers = []
    typeID = request.vars.typeID
    if typeID:
        SetCookie("markers_typeID", typeID)
    else:
        typeID = GetCookie("markers_typeID")

    typeID = int(typeID or 1)
    # we're looking at our own markers, find the actual type
    realTypeID = typeID
    if typeID < 0:
        realTypeID = GetMarkerTypeForPersonal(typeID)
        if realTypeID > 0:
            redirect(GetFullUrlWithout("typeID") + "typeID=%s" % realTypeID)

    typeName = GetMarkerTypeName(typeID)
    isAll = not not request.vars.all
    for r in allMarkers:
        if typeID == r["typeID"]:
            markers.append(r)
        if len(markers) > 100 and not isAll:
            break

    return {
        "typeID"      : typeID,
        "realTypeID"  : realTypeID,
        "markers"     : markers,
        "typeName"    : typeName,
        "markerTypes" : GetMarkerTypes(),
        "manage"      : int(request.vars.manage or 0),
        "categories"  : GetMarkerCategoriesForType(typeID),
        }


@FuncTime
def ViewMarker():
    markerID = int(request.vars.markerID or 0)
    m = GetMarker(markerID)
    tags = GetTagsForLink(TAG_MARKER, markerID)
    return {
        "marker"        : m.marker, 
        "customFields"  : m.customFields,
        "tags"          : tags,
        "starred"       : IsStarred(TAG_MARKER, markerID),
        }

def GetDigestRow(digestID):
    sql = "SELECT * FROM metric.digests WHERE digestID = %d" % digestID
    return dbmetrics.executesql(sql)[0]

def GetDigests():
    sql = """SELECT d.digestID, digestName, d.description, d.createDate, d.modifyDate, d.userName, d.emailSubject, d.emailAddresses, d.disabled, d.scheduleType, d.scheduleDay, d.onlyAlert, numSections=COUNT(DISTINCT s.sectionID), numAlerts=COUNT(DISTINCT a.alertID), numEmails=COUNT(DISTINCT e.digestEmailID) 
               FROM metric.digests d
              LEFT JOIN metric.digestSections s ON s.digestID = d.digestID
              LEFT JOIN metric.digestAlerts a ON a.digestID = d.digestID
              LEFT JOIN metric.digestEmails e ON e.digestID = d.digestID
              GROUP BY d.digestID, digestName, d.description, d.createDate, d.modifyDate, d.userName, d.emailSubject, d.emailAddresses, d.disabled, d.scheduleType, d.scheduleDay, d.onlyAlert
              ORDER BY digestName"""
    response.mainquery.append(sql)
    rows = dbmetrics.executesql(sql)
    digests = GetDictFromRowset(rows)
    return digests

def AddDigestSubscription():
    LoggedIn()
    digestID = int(request.vars.digestID)
    emailAddress = session.userName + "@ccpgames.com"

    sql = "INSERT INTO metric.digestEmails (emailAddress, fullName, createdByUserName, digestID) VALUES ('%s', '%s', '%s', %d)" % (emailAddress, session.fullName.decode("UTF-8"), session.userName, digestID)
    dbmetrics.executesql(sql)
    session.flash = "You are now subscribed to this digest"
    redirect(request.env.http_referer)

def RemoveDigestSubscription():
    LoggedIn()
    digestID = int(request.vars.digestID)
    emailAddress = session.userName + "@ccpgames.com"

    sql = "DELETE FROM metric.digestEmails WHERE digestID = %d AND emailAddress = '%s'" % (digestID, emailAddress)
    dbmetrics.executesql(sql)
    session.flash = "You are no longer subscribed to this digest"
    redirect(request.env.http_referer)

@FuncTime
def Digests():
    digests = GetDigests()
    groupsString = "'bla'"
    if session.groups:
        groupsString = "'" +  "', '".join(session.groups) + "'"
    sql = "SELECT digestID, mailingList FROM metric.digestEmails WHERE emailAddress LIKE '%s%%' OR fullName IN (%s)" % (session.userName, groupsString)
    response.mainquery.append(sql)
    rows = dbmetrics.executesql(sql)
    myDigests = {}
    for r in rows:
        myDigests[r.digestID] = r.mailingList
    ret = {}
    if not request.vars.all:
        for digestID, digest in digests.iteritems():
            if int(request.vars.which or 0) == 2:
                if digest.userName == session.userName:
                    ret[digestID] = digest
            else:
                if digestID in myDigests:
                    ret[digestID] = digest   
    else:
        ret = digests
    return {
    "digests": ret
    }

def DeleteDigest():
    LoggedIn()
    digestID = int(request.vars.digestID)
    sql = "DELETE FROM metric.digestSections WHERE digestID = %d" % digestID
    dbmetrics.executesql(sql)
    sql = "DELETE FROM metric.digestAlerts WHERE digestID = %d" % digestID
    dbmetrics.executesql(sql)
    sql = "DELETE FROM metric.digests WHERE digestID = %d" % digestID
    dbmetrics.executesql(sql)
    sql = "DELETE FROM metric.digestEmails WHERE digestID = %d" % digestID
    dbmetrics.executesql(sql)
    redirect("Digests?message=Digest has been deleted")

@FuncTime
def EditDigest():
    LoggedIn()
    if request.post_vars:
        v = request.post_vars
        digestName = MakeSafe(v.name)
        digestID = int(v.digestID or 0)
        description = MakeSafe(v.description)
        emailAddresses = MakeSafe(v.emailAddresses)
        emailSubject = MakeSafe(v.emailSubject) or digestName
        duplicate = int((v.duplicate == "1"))
        disabled = int((v.isDisabled == "1"))
        onlyAlert = int((v.onlyAlert == "1"))
        sendDescription = int((v.sendDescription == "1"))
        newDigest = (digestID == 0)
        scheduleType = v.scheduleType
        scheduleWeekly = int(v.scheduleWeekly)
        scheduleMonthly = int(v.scheduleMonthly)
        scheduleDay = 0
        if scheduleType == "WEEK":
            scheduleDay = scheduleWeekly
        elif scheduleType == "MONTH":
            scheduleDay = scheduleMonthly
        if duplicate:
            digestID = 0
        if digestID:
            sql = "UPDATE metric.digests SET digestName = '%(digestName)s', description = '%(description)s', modifyDate = GETUTCDATE(), emailSubject = '%(emailSubject)s', emailAddresses = '%(emailAddresses)s', disabled = %(disabled)d, onlyAlert = %(onlyAlert)d, sendDescription = %(sendDescription)d, scheduleType = '%(scheduleType)s', scheduleDay = %(scheduleDay)s WHERE digestID = %(digestID)d" % {
                "digestName"     : digestName,
                "description"    : description,
                "emailSubject"   : emailSubject,
                "emailAddresses" : emailAddresses,
                "disabled"       : disabled,
                "onlyAlert"      : onlyAlert,
                "sendDescription": sendDescription,
                "digestID"       : digestID,
                "scheduleType"   : scheduleType,
                "scheduleDay"    : scheduleDay,
            }
            dbmetrics.executesql(sql)
        else:
            if digestName == "":
                digestName = "%s''s Digest" % session.userName
            sql = """INSERT INTO metric.digests (digestName, description, emailSubject, userName, emailAddresses, disabled, onlyAlert, sendDescription, scheduleType, scheduleDay) VALUES
                ('%(digestName)s', '%(description)s', '%(emailSubject)s', '%(userName)s', '%(emailAddresses)s', %(disabled)d, %(onlyAlert)d, %(sendDescription)d, '%(scheduleType)s', %(scheduleDay)s)""" % {
                "digestName"     : digestName,
                "description"    : description,
                "emailSubject"   : emailSubject,
                "emailAddresses" : emailAddresses,
                "disabled"       : disabled,
                "onlyAlert"      : onlyAlert,
                "sendDescription": sendDescription,
                "userName"       : session.userName,
                "scheduleType"   : scheduleType,
                "scheduleDay"    : scheduleDay,
            }
            dbmetrics.executesql(sql)
            sql = "SELECT TOP 1 digestID FROM metric.digests WHERE userName = '%s' ORDER BY digestID DESC" % session.userName
            digestID = dbmetrics.executesql(sql)[0].digestID

        session.flash = "Digest has been saved."
        if newDigest:
            redirect("EditDigest?digestID=%s" % digestID)
        else:
            redirect("ViewDigest?digestID=%s" % digestID)
    else:
        digestID = int(request.vars.digestID)

        digest = None
        digestSections = []
        digestAlerts = []
        digestEmails = []
        digestName = ""
        description = ""
        emailAddresses = ""
        emailSubject = ""
        scheduleType = "DAY"
        scheduleDay = 1
        disabled = 0
        onlyAlert = 0
        sendDescription = 0
        scheduleWeekly = 1
        scheduleMonthly = 1
        duplicate = int(request.vars.duplicate or 0)
        if digestID > 0:
            sql = "SELECT * FROM metric.digests WHERE digestID = %s" % digestID
            rows = dbmetrics.executesql(sql)
            if not rows:
                return "Digest %s does not exist" % digestID
            digest = rows[0]
            ProcessAccessRules("DIGEST", digestID)

            digestName = digest.digestName
            description = digest.description
            emailAddresses = digest.emailAddresses
            emailSubject = digest.emailSubject
            disabled = digest.disabled
            onlyAlert = digest.onlyAlert
            sendDescription = digest.sendDescription
            scheduleType = digest.scheduleType
            scheduleDay = digest.scheduleDay
            if scheduleType == "WEEK":
                scheduleWeekly = scheduleDay
            elif scheduleType == "MONTH":
                scheduleMonthly = scheduleDay

            # sections
            sql = "SELECT * FROM metric.digestSections WHERE digestID = %d ORDER BY position" % digestID
            digestSections = dbmetrics.executesql(sql)

            # alerts
            sql = "SELECT a.*, title=ISNULL(NULLIF(a.alertTitle, ''), c.counterName) FROM metric.digestAlerts a INNER JOIN zmetric.counters c ON c.counterID = a.counterID WHERE a.digestID = %d ORDER BY a.position" % digestID
            digestAlerts = dbmetrics.executesql(sql)

            # recipients
            sql = "SELECT * FROM metric.digestEmails WHERE digestID = %d ORDER BY cc ASC, mailingList ASC, emailAddress ASC" % digestID
            digestEmails = dbmetrics.executesql(sql)

        sql = "SELECT * FROM metric.digestSectionTemplates"
        rows = dbmetrics.executesql(sql)
        templates = {}
        for r in rows:
            templates[r.templateID] = r
        else:
            emailAddresses = "%s@ccpgames.com" % session.userName
        if duplicate:
            digestName += " (copy)"
        return {
            "digest"        : digest,
            "digestID"      : digestID, 
            "digestSections": digestSections,
            "digestAlerts"  : digestAlerts,
            "digestEmails"  : digestEmails,
            "digestName"    : digestName,
            "description"   : description,
            "emailAddresses": emailAddresses,
            "emailSubject"  : emailSubject,
            "disabled"      : disabled,
            "onlyAlert"     : onlyAlert,
            "sendDescription": sendDescription,
            "duplicate"     : duplicate,
            "scheduleType"  : scheduleType,
            "scheduleWeekly": scheduleWeekly,
            "scheduleMonthly": scheduleMonthly,
            "scheduleDay"   : scheduleDay,
            "templates"     : templates,
            }

@FuncTime
def ViewDigest():
    LoggedIn()
    digestID = int(request.vars.digestID)
    ProcessAccessRules("DIGEST", digestID)

    sql = "SELECT * FROM metric.digests WHERE digestID = %s" % digestID
    rows = dbmetrics.executesql(sql)
    if not rows:
        return "Digest %s does not exist" % digestID
    digest = rows[0]
    digestName = digest.digestName
    description = digest.description
    emailSubject = digest.emailSubject
    disabled = digest.disabled
    onlyAlert = digest.onlyAlert
    sendDescription = digest.sendDescription
    scheduleType = digest.scheduleType
    scheduleDay = digest.scheduleDay
    scheduleWeekly = 0
    scheduleMonthly = 0
    if scheduleType == "WEEK":
        scheduleWeekly = scheduleDay
    elif scheduleType == "MONTH":
        scheduleMonthly = scheduleDay

    # sections
    sql = "SELECT *, urlToClick=NULL FROM metric.digestSections WHERE digestID = %d ORDER BY position" % digestID
    digestSections = dbmetrics.executesql(sql)

    # alerts
    sql = "SELECT a.*, title=ISNULL(NULLIF(a.alertTitle, ''), c.counterName) FROM metric.digestAlerts a INNER JOIN zmetric.counters c ON c.counterID = a.counterID WHERE a.digestID = %d ORDER BY a.position" % digestID
    digestAlerts = dbmetrics.executesql(sql)

    # recipients
    sql = "SELECT * FROM metric.digestEmails WHERE digestID = %d ORDER BY cc ASC, mailingList ASC, emailAddress ASC" % digestID
    digestEmails = dbmetrics.executesql(sql)

    # templates
    sql = "SELECT * FROM metric.digestSectionTemplates"
    rows = dbmetrics.executesql(sql)
    templates = {}
    for r in rows:
        templates[r.templateID] = r

    for r in digestSections:
        urlToClick, urlToSnap = DoGetDigestSectionURL(r.contentType, r.contentConfig)
        r.urlToClick = urlToClick

    tags = GetTagsForLink(TAG_DIGEST, digestID)

    return {
        "digest"        : digest,
        "digestID"      : digestID, 
        "digestSections": digestSections,
        "digestAlerts"  : digestAlerts,
        "digestEmails"  : digestEmails,
        "digestName"    : digestName,
        "description"   : description,
        "emailSubject"  : emailSubject,
        "disabled"      : disabled,
        "onlyAlert"     : onlyAlert,
        "sendDescription": sendDescription,
        "scheduleType"  : scheduleType,
        "scheduleWeekly": scheduleWeekly,
        "scheduleMonthly": scheduleMonthly,
        "scheduleDay"   : scheduleDay,
        "templates"     : templates,
        "tags"          : tags,
        }

def DeleteDigestAlert():
    LoggedIn()
    alertID = int(request.vars.alertID)
    sql = "DELETE FROM metric.digestAlerts WHERE alertID = %d" % alertID
    dbmetrics.executesql(sql)
    session.flash = "Digest alert has been deleted"
    redirect(request.env.http_referer)

def DeleteDigestSection():
    LoggedIn()
    sectionID = int(request.vars.sectionID)
    sql = "DELETE FROM metric.digestSections WHERE sectionID = %d" % sectionID
    dbmetrics.executesql(sql)
    session.flash = "Digest section has been deleted"
    redirect(request.env.http_referer)

@FuncTime
def TestDigestAlert():
    LoggedIn()
    alertID = int(request.vars.alertID)
    digestID = int(request.vars.digestID)

    sql = "SELECT * FROM metric.digests WHERE digestID = %d" % digestID
    digestRow = dbmetrics.executesql(sql)[0]

    sql = "SELECT * FROM metric.digestAlerts WHERE digestID = %(digestID)s ORDER BY position, alertID" % {"digestID": digestID}
    rows = dbmetrics.executesql(sql)
    alerts = []
    for i, r in enumerate(rows):
        if alertID and r.alertID != alertID:
            continue
        a = {"alertID": r.alertID, "alertRow": r}
        config = json.loads(r.config)
        if r.method == "VALUE":
            sql = """EXEC metric.Alerts_CheckValue %(counterID)s, NULL, %(subjectID)s, %(keyID)s, '%(condition)s', %(value)s
            """ % {"counterID": r.counterID, "subjectID": r.subjectID if r.subjectID is not None else "NULL", "keyID": r.keyID or "NULL", "condition": config.get("dir"), "value": config.get("value")}
        elif r.method == "PERCENT":
            sql = """EXEC metric.Alerts_CheckPercent %(counterID)s, NULL, %(subjectID)s, %(keyID)s, %(value)s, %(minValue)s, %(days)s
            """ % {"counterID": r.counterID, "subjectID": r.subjectID if r.subjectID is not None else "NULL", "keyID": r.keyID or "NULL", "value": config.get("value"), "minValue": config.get("minValue"), "days": config.get("days")}
        print sql
        rows = dbmetrics.executesql(sql)
        a["rows"] = rows
        a["sql"] = sql
        alerts.append(a)

    return {
        "alerts"     : alerts,
        "digestID"   : digestID,
        "alertID"    : alertID,
        "digestName" : digestRow.digestName,
    }

def DeleteDigestEmail():
    LoggedIn()
    digestEmailID = int(request.vars.digestEmailID)
    sql = "DELETE FROM metric.digestEmails WHERE digestEmailID = %d" % digestEmailID
    dbmetrics.executesql(sql)
    redirect(request.env.http_referer)


def EditDigestEmails():
    LoggedIn()
    digestID = int(request.vars.digestID)
    emails = request.vars.emails.split(",")
    isCC = int(request.vars.cc)
    userName = session.userName

    existingEmails = set()
    emailsToAdd = set()
    badEmails = set()

    sql = "SELECT emailAddress FROM metric.digestEmails WHERE digestID = %d" % digestID
    rows = dbmetrics.executesql(sql)
    for r in rows:
        existingEmails.add(r.emailAddress.lower())

    for email in emails:
        email = email.lower().strip()
        if not email:
            continue
        if "@" not in email:
            email += "@ccpgames.com"

        recipient = FindRecipientInAD(email)
        if not recipient:
            badEmails.add(email)
            continue
        fullName = recipient[0]
        isMailingList = recipient[1]

        if email in existingEmails:
            continue

        emailsToAdd.add((email, isMailingList, fullName))

    for email, isMailingList, fullName in emailsToAdd:
        sql = "INSERT INTO metric.digestEmails (digestID, emailAddress, fullName, createdByUserName, mailingList, cc) VALUES (%d, '%s', '%s', '%s', %d, %d)" % (digestID, email, fullName, userName, isMailingList, isCC)
        dbmetrics.executesql(sql)

    if badEmails:
        session.flash = "The following emails were not found in Active Directory: %s" % (",".join(badEmails))
    redirect(request.env.http_referer)

@FuncTime
def EditDigestSection():
    LoggedIn()
    sectionID = int(request.vars.sectionID)
    digestID = int(request.vars.digestID)
    if request.post_vars:
        v = request.post_vars
        sectionTitle = MakeSafe(v.sectionTitle)
        position = v.position
        description = MakeSafe(v.description)
        contentType = v.contentType
        if v.headeronly:
            contentType = "HEADER"
        width = (v.width or None)
        height = (v.height or None)
        zoom = (v.zoom or None)
        duplicate = not not v.duplicate
        widthApplyToAll = not not v.widthApplyToAll
        heightApplyToAll = not not v.heightApplyToAll
        zoomApplyToAll = not not v.zoomApplyToAll
        contentConfig = v.contentConfig
        templateID = v.templateID
        if sectionID and not duplicate:
            sql = "UPDATE metric.digestSections SET sectionTitle = '%(sectionTitle)s', description = '%(description)s', position = %(position)s, contentType = '%(contentType)s', contentConfig = '%(contentConfig)s', width = %(width)s, height = %(height)s, zoom = %(zoom)s, templateID = %(templateID)s WHERE sectionID = %(sectionID)d" % {
                "sectionTitle" : sectionTitle,
                "description" : description,
                "position" : SqlIntOrNULL(position),
                "contentType" : contentType,
                "contentConfig" : contentConfig,
                "width" : SqlIntOrNULL(width),
                "height" : SqlIntOrNULL(height),
                "zoom" : SqlFloatOrNULL(zoom),
                "sectionID" : sectionID,
                "templateID" : SqlIntOrNULL(templateID),
            }
        else:
            topPosition = 0
            sql = "SELECT TOP 1 IsNull(position, 0) FROM metric.digestSections WHERE digestID = %d ORDER BY position DESC" % digestID
            try:
                topPosition = dbmetrics.executesql(sql)[0][0] + 1
            except:
                pass
            sql = """INSERT INTO metric.digestSections (sectionTitle, description, position, contentType, contentConfig, width, height, zoom, digestID, templateID) VALUES
            ('%(sectionTitle)s', '%(description)s', %(position)s, '%(contentType)s', '%(contentConfig)s', %(width)s, %(height)s, %(zoom)s, %(digestID)d, %(templateID)s)
                """ % {
                "sectionTitle" : sectionTitle,
                "description" : description,
                "position" : SqlIntOrNULL(topPosition),
                "contentType" : contentType,
                "contentConfig" : contentConfig,
                "width" : SqlIntOrNULL(width),
                "height" : SqlIntOrNULL(height),
                "zoom" : SqlFloatOrNULL(zoom),
                "digestID" : digestID,
                "templateID" : SqlIntOrNULL(templateID),
            }
        dbmetrics.executesql(sql)

        if widthApplyToAll:
            sql = "UPDATE metric.digestSections SET width = %s WHERE digestID = %s" % (SqlIntOrNULL(width), digestID)
            dbmetrics.executesql(sql)
        if heightApplyToAll:
            sql = "UPDATE metric.digestSections SET height = %s WHERE digestID = %s" % (SqlIntOrNULL(height), digestID)
            dbmetrics.executesql(sql)
        if zoomApplyToAll:
            sql = "UPDATE metric.digestSections SET zoom = %s WHERE digestID = %s" % (SqlFloatOrNULL(zoom), digestID)
            dbmetrics.executesql(sql)
        redirect("EditDigest?digestID=%s" % digestID)
    else:
        sql = "SELECT * FROM metric.digests WHERE digestID = %d" % digestID
        digestRow = dbmetrics.executesql(sql)[0]

        position = int(request.vars.position or 0)
        sectionTitle = ""
        description = ""
        contentConfig = ""
        zoom = ""
        width = ""
        height = ""
        contentType = "GRAPH"
        templateID = ""
        contentConfigString = ""
        if sectionID:
            sql = "SELECT * FROM metric.digestSections WHERE sectionID = %d" % sectionID
            r = dbmetrics.executesql(sql)[0]
            position = r.position
            sectionTitle = r.sectionTitle or ""
            description = r.description or ""
            contentType = r.contentType
            width = r.width
            height = r.height
            zoom = r.zoom
            templateID = r.templateID
            contentConfigString = r.contentConfig
            contentConfig = None
            try:
                contentConfig = json.loads(contentConfigString)
            except:
                pass

        sql = "SELECT * FROM metric.digestSectionTemplates WHERE templateType = 'SECTION' ORDER BY templateName ASC"
        templates = dbmetrics.executesql(sql)

        if request.vars.duplicate:
            sectionTitle += " (copy)"
            position += 1
        return {
            "digestID"      : digestRow.digestID,
            "digestName"    : digestRow.digestName,

            "sectionID"     : sectionID,
            "position"      : position,
            "sectionTitle"  : sectionTitle,
            "description"   : description,
            "contentType"        : contentType,
            "width"         : width,
            "height"        : height,
            "zoom"          : zoom,
            "templateID"    : templateID,
            "contentConfigString" : contentConfigString,
            "contentConfig" : contentConfig,
            "templates"     : templates,
        }


@FuncTime
def EditDigestAlert():
    LoggedIn()
    alertID = int(request.vars.alertID)
    digestID = int(request.vars.digestID)
    if request.post_vars:
        v = request.post_vars
        alertTitle = MakeSafe(v.alertTitle)
        description = MakeSafe(v.description)
        counterID = int(v.counterID or 0)
        subjectID = (v.subjectID or None)
        severity = v.severity
        duplicate = not not v.duplicate
        templateID = v.templateID or None
        if subjectID:
            subjectID = int(subjectID)
        keyID = (v.keyID or None)
        if keyID:
            keyID = int(keyID)
        method = MakeSafe(v.method)

        if not counterID or not method:
            print v
            return "You must select a counter and an alert method"

        config = {}
        for vv in v:
            if vv.startswith("config"):
                lst = vv.split("_")

                thisMethod = lst[1]
                thisKey = lst[2]
                thisVal = getattr(v, vv)
                try:
                    thisVal = int(thisVal)
                except:
                    try:
                        thisVal = float(thisVal)
                    except:
                        pass
                if thisMethod == method:
                    config[thisKey] = thisVal
        configString = json.dumps(config)
        if alertID > 0 and not duplicate:
            sql = """
UPDATE metric.digestAlerts SET templateID = %(templateID)s, severity = %(severity)s, alertTitle = '%(alertTitle)s', description = '%(description)s', counterID = %(counterID)s, subjectID = %(subjectID)s, keyID = %(keyID)s, method = '%(method)s', config = '%(config)s' WHERE alertID = %(alertID)d
            """ % {
            "alertTitle": alertTitle,
            "description": description,
            "counterID": counterID,
            "subjectID": SqlIntOrNULL(subjectID, True),
            "keyID": SqlIntOrNULL(keyID, True),
            "templateID": SqlIntOrNULL(templateID, True),
            "method": method,
            "config": configString,
            "alertID" : alertID,
            "severity" : severity,
            }
        else:
            sql = """
INSERT INTO metric.digestAlerts (templateID, severity, alertTitle, description, counterID, subjectID, keyID, method, config, digestID) VALUES (%(templateID)s, %(severity)s, '%(alertTitle)s', '%(description)s', %(counterID)s, %(subjectID)s, %(keyID)s, '%(method)s', '%(config)s', %(digestID)d)
            """ % {
            "alertTitle": alertTitle,
            "description": description,
            "counterID": counterID,
            "subjectID": SqlIntOrNULL(subjectID, True),
            "keyID": SqlIntOrNULL(keyID, True),
            "templateID": SqlIntOrNULL(templateID, True),
            "method": method,
            "config": configString,
            "digestID" : digestID,
            "severity" : severity,
            }
        dbmetrics.executesql(sql)
        redirect("EditDigest?digestID=%s" % digestID)
    else:
        sql = "SELECT * FROM metric.digests WHERE digestID = %d" % digestID
        digestRow = dbmetrics.executesql(sql)[0]

        position = int(request.vars.position or 0)
        alertTitle = ""
        description = ""
        counterID = None
        counterName = ""
        subjectID = 0
        subjectText = ""
        keyID = 0
        keyText = ""
        method = ""
        severity = 3
        templateID = ""
        config = {}
        if alertID:
            sql = "SELECT * FROM metric.digestAlerts WHERE alertID = %d" % alertID
            r = dbmetrics.executesql(sql)[0]
            position = r.position or 0
            alertTitle = r.alertTitle or ""
            description = r.description or ""
            counterID = r.counterID
            subjectID = r.subjectID
            keyID = r.keyID
            method = r.method
            severity = r.severity
            templateID = r.templateID or ""
            config = json.loads(r.config)
        elif request.vars.counterID:
            counterID = int(request.vars.counterID)
            subjectID = int(request.vars.columnID)
            keyID = int(request.vars.keyID)

        if counterID:
            sql = "SELECT counterName FROM zmetric.counters WHERE counterID = %d" % counterID
            try:
                counterName = dbmetrics.executesql(sql)[0].counterName
            except:
                pass
        sql = "SELECT * FROM metric.digestSectionTemplates WHERE templateType = 'ALERT' ORDER BY templateName ASC"
        templates = dbmetrics.executesql(sql)

        if subjectID or keyID:
            subjectText, keyText = GetGraphText(counterID, (subjectID or 0), (keyID or 0))

        if request.vars.duplicate:
            alertTitle += " (copy)"
            position += 1

        return {
            "digestID"      : digestRow.digestID,
            "digestName"    : digestRow.digestName,

            "alertID"       : alertID,
            "position"      : position,
            "alertTitle"    : alertTitle,
            "description"   : description,
            "counterID"     : counterID,
            "counterName"   : counterName,
            "subjectID"     : subjectID,
            "subjectText"   : subjectText,
            "keyID"         : keyID,
            "keyText"       : keyText,
            "method"        : method,
            "config"        : config,
            "severity"      : severity,
            "templateID"    : templateID,
            "templates"     : templates,
        }


def SendDigest():
    digestID = int(request.vars.digestID)
    emailAddress = request.vars.email
    args = ["python.exe", "SendDigest.py", "--digest=%s" % digestID]
    if emailAddress:
        args.append("--email=%s" % emailAddress)
    print  os.getcwd()

    from win32process import DETACHED_PROCESS, CREATE_NEW_PROCESS_GROUP

    p = subprocess.Popen(args, close_fds=True, creationflags=DETACHED_PROCESS|CREATE_NEW_PROCESS_GROUP, cwd="../Phantomjs/")
    session.flash = "Digest creation for %s has been queued up.<br>It might take a few minutes for your digest to be delivered." % emailAddress
    redirect(request.env.http_referer)

def GetDigestSectionURL():
    contentType = request.vars.contentType
    contentConfig = request.vars.contentConfig
    urlToSnap, urlToClick = DoGetDigestSectionURL(contentType, contentConfig)
    if not urlToSnap:
        if contentType == "HEADER":
            return response.json("Error: This is just a header")
        else:
            return response.json("Error: Unknown contentType %s" % contentType)
    return response.json([urlToSnap, urlToClick])

def DoGetDigestSectionURL(contentType, contentConfig):
    if contentType == "HEADER":
        return None, None
    contentConfig = str(contentConfig)
    try:
        contentConfig = json.loads(contentConfig)
    except Exception as e:
        return None, None
    if contentType == "GRAPH":
        urlToSnap = "EmbeddedCounters?"
        for cfg in contentConfig:
            urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
        urlToClick = urlToSnap.replace("Embedded", "")
    elif contentType == "DASHBOARD":
        urlToSnap = "EmbeddedDashboard?"
        for cfg in contentConfig:
            urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
        urlToClick = urlToSnap.replace("Embedded", "")
        urlToSnap += "embedded=1&nomargin=1&hidetitle=1"
    elif contentType == "DASHBOARDGRAPHS":
        urlToSnap = "EmbeddedDashboardGraphs?"
        for cfg in contentConfig:
            urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
        urlToClick = urlToSnap.replace("Embedded", "")
    elif contentType == "REPORT":
        urlToSnap = "EmbeddedReport?"
        for cfg in contentConfig:
            urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
        urlToClick = urlToSnap.replace("Embedded", "")
        urlToSnap += "hidetitle=1&hideids=1"
    elif contentType == "NUMBER":
        urlToSnap = "FetchCount?"
        for cfg in contentConfig:
            urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
        urlToClick = urlToSnap.replace("FetchCount", "Report")
        urlToSnap += "style=font-family:Verdana font-size:24px color:green"
    else:
        return None, None
    return urlToClick, urlToSnap


def EditDigestParseUrl():
    from urlparse import urlparse
    num = int(request.vars.num)
    url = request.vars.url
    p = urlparse(url)
    path = p.path
    query = p.query.replace("amp;", "&")
    controller = path.split("/")[-1]
    contentType = {"FetchCount" : "NUMBER", "Counters" : "GRAPH", "Dashboard" : "DASHBOARD", "Report" : "REPORT", "DashboardGraphs" : "DASHBOARDGRAPHS"}.get(controller, None)
    argumentList = []
    err = ""
    contentConfigTable = "<table class=\"configVals\"><tr><th>Key</th><th>Value</th></tr>"
    if not contentType:
        err = "Unsupported controller method: %s" % controller
    else:
        args = query.split("&")
        for a in sorted(args):
            if "=" in a:
                lst = a.split("=")
                if lst[0] not in ("w", "h", "dt"):
                    argumentList.append([lst[0], lst[1]])
                    contentConfigTable += "<tr><td>%s</td><td>%s</td></tr>" % (lst[0], lst[1])
    

    contentConfigTable += "</table>"
    contentConfig = json.dumps(argumentList)
    for arg in argumentList:
        k = arg[0]
        v = arg[1]
        print k, v
        if k == "counterID":
            if IsRestricted("COUNTER", int(v)):
                err = "Content is restricted"
                contentConfigTable = ""
        if k == "collectionID":
            if IsRestricted("COLLECTION", int(v)):
                err = "Content is restricted"
                contentConfigTable = ""
        if k == "dashboardID":
            if IsRestricted("DASHBOARD", int(v)):
                err = "Content is restricted"
                contentConfigTable = ""

    digestTitle = ""
    ret = {"num" : num, "contentType" : contentType, "contentConfig" : contentConfig, "error" : err, "contentConfigTable": contentConfigTable}
    return response.json(ret)

def IsLocal():
    return "127.0.0.1" in request.client.lower()

def LoggedIn(isAdmin=False):
    if IsLocal():
        return True
    if not session.userName:
        redirect(URL("Login?redirect=%s" % GetFullUrl()))
    elif isAdmin and not session.admin:
        redirect(URL("Admin?redirect=%s" % GetFullUrl()))

def GetTeamForUser(userName):
    return ""
#    sql = "???" % userName
#    DATABASE_IP     = "?"
#    DATABASE_LOGIN  = "?"
#    DATABASE_PASSW  = "?"
#    DATABASE_DB     = "?"
#    WEB_URL         = "http://?"
#    dbDT = SQLDB('mssql://%s:%s@%s/%s' % (DATABASE_LOGIN, DATABASE_PASSW, DATABASE_IP, DATABASE_DB), check_reserved=['mssql']) 
#    try:
#        row = dbDT.executesql(sql)[0]
#        return row.SprintName
#    except:
#        return None

@FuncTime
def DeleteMarker():
    LoggedIn()
    markerID = int(request.vars.markerID or 0)
    typeID = int(request.vars.typeID or 0)
    sql = "UPDATE markers SET deleted = 1 WHERE markerID = %d" % markerID
    dbmetrics.executesql(sql)

    cache.ram.clear()
    redirect("Markers?typeID=%d" % typeID)


def AddMarkerFromGraph():
    LoggedIn()
    title = MakeSafe(request.vars.title)
    dt = MakeSafe(request.vars.date)
    typeID = GetMarkerTypeForPersonal(-1, True)
    sql = """
        INSERT INTO markers (title, typeID, dateTime, userNameCreated)
           VALUES ('%(title)s', %(typeID)d, '%(dateTime)s', '%(userName)s')
    """ % {"title": title, "typeID": typeID, "dateTime": dt, "userName": session.userName}
    dbmetrics.executesql(sql)
    redirect(request.env.http_referer)


@FuncTime
def AddMarker():
    LoggedIn()
    typeID = int(request.vars.typeID or 0)
    markerID = int(request.vars.markerID or 0)
    marker = None
    important = False
    if typeID < 0:
        typeID = GetMarkerTypeForPersonal(typeID, True)

    if markerID:
        marker = GetMarker(markerID).marker
        typeID = marker.typeID

    sql = "SELECT * FROM markerTypeColumns WHERE markerTypeID = %s ORDER BY title ASC" % typeID
    rows = dbmetrics.executesql(sql)
    markerTypeColumns = GetDictFromRowset(rows)

    if request.post_vars:
        v = request.post_vars
        title = MakeSafe(v.title)
        description = MakeSafe(v.description)
        dateTime = MakeSafe(v.dateTime)
        dateTime_hour = int(v.dateTime_hour or 0)
        dateTime_minute = int(v.dateTime_minute or 0)
        dateTime = dateTime + " %s:%s" % (dateTime_hour, dateTime_minute)
        important = 1 if v.important else 0
        typeID = int(v.typeID)
        url = MakeSafe(v.url)
        categoryID = int(v.categoryID or 0)
        if markerID:
            sql = """
                UPDATE markers 
                   SET title = '%(title)s', description = '%(description)s', important = %(important)d,
                   categoryID = %(categoryID)d, url = '%(url)s', typeID = %(typeID)d,
                   dateTime = '%(dateTime)s', dateTimeEdited = GetUTCDate(), userNameEdited = '%(userName)s'
                 WHERE markerID = %(markerID)d
            """
        else:
            sql = """
                INSERT INTO markers (title, description, categoryID, url, typeID, dateTime, userNameCreated, important)
                   VALUES ('%(title)s', '%(description)s', %(categoryID)d, '%(url)s', %(typeID)d, '%(dateTime)s', '%(userName)s', %(important)d)
            """
        sql = sql % {
            "title"       : title, 
            "description" : description, 
            "categoryID"  : categoryID, 
            "url"         : url, 
            "markerID"    : markerID,
            "dateTime"    : dateTime,
            "typeID"      : typeID,
            "userName"    : session.userName,
            "important"   : important,
            }
        cache.ram("markers", None, 0) 
        dbmetrics.executesql(sql)

        if not markerID:
            sql = "SELECT TOP 1 markerID FROM markers ORDER BY markerID DESC"
            markerID = dbmetrics.executesql(sql)[0].markerID
            if session.teamName:
                DoAddTag(TAG_MARKER, markerID, session.teamName)
        else:
            sql = "DELETE FROM markerColumnValues WHERE markerID = %s" % markerID
            dbmetrics.executesql(sql)

        # update extra columns
        for markerColumnID in markerTypeColumns.iterkeys():
            val = getattr(v, "markerColumnID_%s" % markerColumnID, "")
            if not val:
                val = ""
            sql = "INSERT INTO markerColumnValues (markerID, markerColumnID, value) VALUES (%d, %d, '%s')" % (markerID, markerColumnID, val)
            dbmetrics.executesql(sql)

        sql = ""
        cache.ram.clear()

        redirect("ViewMarker?markerID=%s" % markerID)

    markerColumnValues = {}
    if markerID:
        sql = """
            SELECT v.markerColumnID, value FROM markerColumnValues v
              INNER JOIN markerTypeColumns c ON c.markerColumnID = v.markerColumnID
             WHERE v.markerID = %s
        """ % markerID
        rows = dbmetrics.executesql(sql)
        markerColumnValues = GetDictFromRowset(rows)

    return {
        "markerTypes" : GetMarkerTypes(),
        "categories"  : GetMarkerCategoriesForType(typeID),
        "error"       : None,
        "markerTypeColumns": markerTypeColumns,
        "markerColumnValues" : markerColumnValues,
        "typeID"      : typeID,
        "marker"      : marker,
        "markerID"    : markerID,
        }


@FuncTime
def ManageMarkerCategories():
    LoggedIn(True)
    typeID = request.vars.typeID
    if typeID:
        SetCookie("markers_typeID", typeID)
    else:
        typeID = GetCookie("markers_typeID")
    typeID = int(typeID or 1)

    sql = """
  SELECT c.categoryID, c.title, numMarkers=COUNT(m.markerID)
    FROM markerTypeCategories c
      LEFT JOIN markers m ON m.categoryID = c.categoryID
   WHERE c.markerTypeID = %d
   GROUP BY c.categoryID, c.title
   ORDER BY c.title ASC
    """ % typeID
    response.query.append(sql)
    rows = dbmetrics.executesql(sql)
    return {
        "markerTypeCategories" : rows,
        "typeName"             : GetMarkerTypeName(typeID),
        "markerTypes"          : GetMarkerTypes(),
        "typeID"               : typeID,
    }


@FuncTime
def EditMarkerCategory():
    LoggedIn(True)
    if request.post_vars:
        v = request.post_vars
        title = MakeSafe(v.title)
        description = MakeSafe(v.description)
        typeID = int(v.typeID or 0)
        categoryID = int(v.categoryID or 0)
        if not title:
            return "You must specify a title"
        if categoryID:
            sql = "UPDATE markerTypeCategories SET title = '%s', description = '%s' WHERE categoryID = %d" % (title, description, categoryID)
        else:
            if not typeID:
                return "You must specify a type"
            sql = "INSERT INTO markerTypeCategories (title, description, markerTypeID) VALUES ('%s', '%s', %s)" % (title, description, typeID)
        dbmetrics.executesql(sql)
        cache.ram.clear()
        redirect("/ManageMarkerCategories")

    title = ""
    description = ""
    categoryID = int(request.vars.categoryID)
    typeID = int(request.vars.typeID or 1)
    if categoryID:
        sql = """SELECT * FROM markerTypeCategories WHERE categoryID = %d""" % categoryID
        row = dbmetrics.executesql(sql)[0]
        title = row.title
        description = row.description
    return {
        "categoryID" : categoryID,
        "title"      : title,
        "description": description,
        "typeID"     : typeID,
    }


@FuncTime
def DeleteMarkerCategory():
    LoggedIn(True)
    categoryID = int(request.vars.categoryID)
    sql = """SELECT * FROM markers WHERE categoryID = %d""" % categoryID
    rows = dbmetrics.executesql(sql)
    if len(rows) > 0:
        return "You cannot delete a non-empty category. Please move all the markers in this category somewhere else."

    sql = "DELETE FROM markerTypeCategories WHERE categoryID = %d" % categoryID
    dbmetrics.executesql(sql)
    redirect("ManageMarkerCategories")


@FuncTime
def MoveMarkersToCategory():
    markers = request.vars.chk
    toCategoryID = int(request.vars.toCategoryID or 0)
    if not toCategoryID:
        return "You must select a category"
    if type(markers) != types.ListType:
        markers = [markers]
    for m in markers:
        sql = "UPDATE markers SET categoryID = %d where markerID = %d" % (toCategoryID, int(m))
        dbmetrics.executesql(sql)
    cache.ram.clear()
    redirect("Markers?categoryID=%s" % toCategoryID)

def GetCounters():
    return cache.ram("counters", lambda:DoGetCounters(), CACHE_TIME_FOREVER)


def DoGetCounters():
    sql = """
        SELECT *
          FROM zmetric.countersEx
         ORDER BY groupOrder, groupName, [order], counterName
    """
    rows = dbmetrics.executesql(sql)
    ret = collections.OrderedDict()
    for r in rows:
        ret[r.counterID] = r
    return ret


def GetCollections():
    return cache.ram("collections", lambda:DoGetCollections(), CACHE_TIME_FOREVER)


def DoGetCollections():
    sql = """
    SELECT c.*, g.groupName
      FROM metric.collections c
        LEFT JOIN zmetric.groups g ON g.groupID = c.groupID
     ORDER BY ISNULL(g.[order], 9999), ISNULL(g.groupName, 'zzzz'), collectionName ASC
    """
    LogQuery(sql)
    collectionRows = dbmetrics.executesql(sql, as_dict=True) # return as a dict so that we can enumerate the columns

    sql = """
        SELECT cc.*, c.groupID, g.groupName, ccc.columnName
          FROM metric.collectionCountersEx cc
          INNER JOIN zmetric.countersEx c ON c.counterID = cc.counterID
          INNER JOIN zmetric.groups g ON g.groupID = c.groupID
           LEFT JOIN zmetric.columns ccc ON ccc.counterID = cc.counterID AND ccc.columnID = cc.subjectID
        ORDER BY cc.collectionID, [collectionIndex] ASC
    """
    LogQuery(sql)
    countersRows = dbmetrics.executesql(sql)
    countersByCollection = collections.defaultdict(list)
    ret = collections.OrderedDict()

    for r in countersRows:
        countersByCollection[r.collectionID].append(r)

    for r in collectionRows:
        collectionID = r["collectionID"]
        kv = KeyVal()
        for k, v in r.iteritems():
            if k == "config":
                if v:
                    kv.config = json.loads(v)
                else:
                    kv.config = {}
                for cfgKey, cfgVal in kv.config.iteritems():
                    newVal = cfgVal
                    if cfgVal == "None":
                        newVal = None
                    elif cfgVal == "False":
                        newVal = False
                    elif cfgVal == "True":
                        newVal = True
                    kv.config[cfgKey] = newVal
            else:
                setattr(kv, k, v)
        kv.counters = countersByCollection.get(collectionID, None)
        ret[collectionID] = kv

    return ret


def GetCollection(collectionID):
    if collectionID not in GetCollections():
        cache.ram("collections", None, 0)

    return GetCollections().get(int(collectionID))


def GetCounterSubjects(counterID):
    relevantIDs = set()
    sql = """
        SELECT DISTINCT subjectID
          FROM zmetric.dateCountersEx 
         WHERE counterID = %s AND counterDate > GETUTCDATE()-30
         ORDER BY subjectID
    """ % counterID
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        relevantIDs.add(r.subjectID)

    
    sql = """
        SELECT v.lookupID, v.lookupText
          FROM zmetric.counters c
            LEFT JOIN zsystem.lookupValues v ON v.lookupTableID = c.subjectLookupTableID
         WHERE c.counterID = %(counterID)s
         ORDER BY ISNULL(v.fullText, v.lookupText)
    """ % {"counterID": counterID}
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)

    # we didn't find anything, let's check whether we have columns instead
    if not rows or (len(rows) == 1 and not rows[0].lookupID):
        sql = """
            SELECT columnID AS lookupID, columnName AS lookupText
              FROM zmetric.columnsEx 
             WHERE counterID = %(counterID)s
        """ % {"counterID": counterID}
        LogQuery(sql)
        rows = dbmetrics.executesql(sql)
    ret = []
    for r in rows:
        if r.lookupID in relevantIDs or not relevantIDs:
            ret.append(r)
    return ret


def GetCounterKeys(counterID):
    relevantIDs = set()
    sql = """
        SELECT TOP 3000 keyID, COUNT(*)
          FROM zmetric.dateCounters
         WHERE counterID = %s AND counterDate > GETUTCDATE()-30
         GROUP BY keyID
         ORDER BY 2 DESC
    """ % counterID
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        relevantIDs.add(r.keyID)
    sql = """
        SELECT v.lookupID, ISNULL(v.fullText, v.lookupText) AS lookupText
          FROM zmetric.counters c
            LEFT JOIN zsystem.lookupValuesEx v ON v.lookupTableID = c.keyLookupTableID
         WHERE c.counterID = %(counterID)s
         ORDER BY ISNULL(v.fullText, v.lookupText)
    """ % {"counterID": counterID}
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    ret = []
    for r in rows:
        if r.lookupID in relevantIDs:
            ret.append(r)
    return ret


def GetGraphText(counterID, subjectID, keyID):
    sql = "EXEC metric.Counters_GraphText %d, %d, %d" % (counterID, subjectID, keyID)
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    subjectText = rows[0].subjectText
    keyText     = rows[0].keyText
    columnName = rows[0].columnName
    return (subjectText or columnName), keyText


def PopulateCounterForm():
    counterID = int(request.vars.counterID)
    subjects = GetCounterSubjects(counterID)
    keys = GetCounterKeys(counterID)

    return response.json({"keyID": keys, "subjectID": subjects})


def LoadAddToContainer():
    which = request.vars.which
    page = request.vars.page
    columns = []
    counterID = 0
    if page == "Report":
        counterID = int(request.vars.counterID)
        sql = "SELECT columnID, columnName FROM zmetric.columns WHERE counterID = %d ORDER BY columnName ASC" % counterID
        rows = dbmetrics.executesql(sql)
        if rows:
            columns = rows

    collections_ = GetCollections()
    collections = {}
    for collectionID, collection in collections_.iteritems():
        if collection.userName == session.userName or request.vars.all:
            collections[collectionID] = collection

    digests_ = GetDigests()
    digests = {}
    for digestID, digest in digests_.iteritems():
        if digest.userName == session.userName or request.vars.all:
            digests[digestID] = digest

    return {
        "which"       : which,
        "page"        : page,
        "collections" : collections,
        "digests"     : digests,

        "columns"     : columns,
        "counterID"   : counterID,
        }


def GetColumnsForCounter():
    counterID = int(request.vars.counterID)
    sql = "SELECT columnID, columnName FROM zmetric.columns WHERE counterID = %d ORDER BY columnID ASC" % counterID
    rows = dbmetrics.executesql(sql)
    ret = []
    if not rows:
        ret = [[0, "value"]]
    for r in rows:
        ret.append([r.columnID, r.columnName])
    return response.json(ret)


def SearchCounters():
    term = request.vars.term.lower()
    num = 50
    ret = []
    if term == "all":
        sql = "SELECT counterID, counterName, groupName FROM zmetric.countersEx WHERE hidden = 0 AND obsolete = 0 ORDER BY groupName ASC, counterName ASC"
        rows = dbmetrics.executesql(sql)
        for r in rows:
            ret.append({"id": r.counterID, "name": "%s / %s" % (r.groupName, r.counterName)})
        return response.json(ret)
    else:
        sql = """
            SELECT TOP %(num)s counterID, counterName, groupName 
              FROM zmetric.countersEx 
             WHERE hidden = 0 AND obsolete = 0 AND LOWER(counterName) LIKE '%%%(term)s%%' OR LOWER(groupName) LIKE '%%%(term)s%%'
             ORDER BY groupName ASC, counterName ASC
        """ % {"term": term, "num": num}
        rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
        for r in rows:
            ret.append({"id": r.counterID, "name": "%s / %s" % (r.groupName, r.counterName)})

        return response.json(ret)


def SearchKeys():
    counterID = int(request.vars.counterID or 0)
    term = request.vars.term.lower()
    num = 10
    if term == "all":
        rows = GetCounterKeys(counterID)
        ret = []
        for r in rows:
            ret.append({"id": r.lookupID, "name": r.lookupText})
        return response.json(ret)
    else:
        sql = """
            SELECT TOP %(num)s v.lookupID, ISNULL(v.fullText, v.lookupText) AS lookupText
              FROM zmetric.counters c
                LEFT JOIN zsystem.lookupValuesEx v ON v.lookupTableID = c.keyLookupTableID
             WHERE c.counterID = %(counterID)s AND LOWER(v.lookupText) LIKE '%(term)s%%'
             ORDER BY v.lookupText
        """ % {"counterID": counterID, "term": term, "num": num}
        rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
        ret = []
        for r in rows:
            ret.append({"id": r.lookupID, "name": r.lookupText})

        return response.json(ret)


def SearchSubjects():
    counterID = int(request.vars.counterID or 0)
    term = request.vars.term.lower()
    num = 10
    if term == "all":
        rows = GetCounterSubjects(counterID)
        ret = []
        for r in rows:
            ret.append({"id": r.lookupID, "name": r.lookupText})
        return response.json(ret)
    else:
        sql = """
            SELECT TOP %(num)s v.lookupID, ISNULL(v.fullText, v.lookupText) AS lookupText
              FROM zmetric.counters c
                LEFT JOIN zsystem.lookupValuesEx v ON v.lookupTableID = c.subjectLookupTableID
             WHERE c.counterID = %(counterID)s AND LOWER(ISNULL(v.fullText, v.lookupText)) LIKE '%%%(term)s%%'
             ORDER BY ISNULL(v.fullText, v.lookupText)
        """ % {"counterID": counterID, "term": term, "num": num}
        #rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
        rows = dbmetrics.executesql(sql)
        ret = []
        for r in rows:
            ret.append({"id": r.lookupID, "name": r.lookupText})

    return response.json(ret)

#
# Counters
#

@cache(request.env.web2py_original_uri,time_expire=300,cache_model=cache.ram)
def CustomGraph():
    return DoCounters(False)

def EmbeddedCounters():
    return DoCounters(False)

@FuncTime
def Counters():
    if request.vars.action:
        return DoCounterAction(request.vars.action, request.vars.actionContext)
    if request.vars.cmd:
        cmd = request.vars.cmd
        collectionID = int(request.vars.collectionID)
        if cmd == "savecollection":
            UpdateCollection(collectionID)
            redirect("Counters?collectionID=%s" % collectionID)
        elif cmd in ("addtocollection", "newcollection"):
            newCollectionID = AddNewToCollection()
            if cmd == "newcollection":
                UpdateCollection(newCollectionID)
            if newCollectionID != collectionID:
                redirect("EditCollection?collectionID=%s&new=1" % newCollectionID)
            else:
                redirect("Counters?collectionID=%s" % collectionID)

    return DoCounters()

def DoCounterAction(action, ctx):
    if "move" in action.lower():
        urlFields = GetCurrentUrlFieldsWithout(["action", "actionContext"])
        graphs = urlFields.get("graph")
        if isinstance(graphs, str):
            graphs = [graphs]
        if not graphs:
            graphs = []
        isTop = False
        for g in graphs:
            l = [int(c) for c in g.split("_")]
            if l[1] < 0 or l[2] < 0:
                isTop = True
                break
        if isTop:
            urlFields["message"] = "You cannot perform this action on a TOP X chart page."
            url = URL(r=request, f='', vars=urlFields)
            redirect(url)


    skipFields = set(["action", "actionContext", "counterID", "graph", "subjectID" , "keyID", "message"])

    # if we have a collection pull out all the config and then override it with passed in values
    urlFields = {}
    if request.vars.collectionID:
        collectionID = int(request.vars.collectionID)
        config = GetCollection(collectionID).config
        for k, v in config.iteritems():
            if not k.startswith("cfg"): # skip the chart configs, they are dealt with specifically
                if isinstance(v, bool):
                    v = int(v)
                urlFields[k] = v
        #print "Got urlFields from config: %s" % urlFields

    passedInUrlFields = GetCurrentUrlFieldsWithout(skipFields)
    urlFields.update(passedInUrlFields)
    url = ""#GetCurrentUrlWithout(",".join(skipFields))
    graphList = []
    if request.vars.graph:
        graphList = request.vars.graph
        if isinstance(graphList, str):
            graphList = [graphList]
    elif request.vars.counterID:
        graphList = ["%s_%s_%s" % (request.vars.counterID, request.vars.subjectID, request.vars.keyID)]

    elif request.vars.collectionID:
        collection = GetCollection(int(request.vars.collectionID))
        for c in collection.counters:
            graphList.append("%s_%s_%s" % (c.counterID, c.subjectID, c.keyID))

    if action == "PullOutSelectedChart":
        graphList = [ctx]
    elif action == "RemoveSelectedChart":
        #return "%s vs. %s" % (graphList, ctx)
        graphList.remove(ctx)
        #return "%s vs. %s" % (graphList, ctx)
    elif action == "MoveSelectedChartToTop":
        graphList.remove(ctx)
        graphList.insert(0, ctx)
    elif action == "MoveSelectedChartToBottom":
        graphList.remove(ctx)
        graphList.append(ctx)
    elif action == "MoveSelectedChartDown":
        idx = graphList.index(ctx)
        if idx < len(graphList)-1:
            graphList.remove(ctx)
            graphList.insert(idx+1, ctx)
    elif action == "MoveSelectedChartUp":
        idx = graphList.index(ctx)
        if idx > 0:
            graphList.remove(ctx)
            graphList.insert(idx-1, ctx)
    elif action in ("NormalizeSelectedChart", "NormalizeSelectedChartAndRemove"):
        skipFields.add("normalize")
        try:
            urlFields.remove("normalize")
        except:
            pass
        urlFields["normalize"] = ctx
        if action == "NormalizeSelectedChartAndRemove":
            graphList.remove(ctx)
    elif action == "CopySelectedChart":
        SetCookie("copiedChart", ctx)
        urlFields["message"] = "The chart has been copied. You can paste it into other charts now."
    elif action in ("PasteChartBefore", "PasteChartAfter"):
        copiedChart = GetCookie("copiedChart")
        if not copiedChart:
            urlFields["message"] = "You first need to copy a chart."
        else:
            if ctx == copiedChart:
                pass
            else:
                if copiedChart in graphList:
                    graphList.remove(copiedChart)
                idx = graphList.index(ctx)
                graphList.insert(idx+(1 if action == "PasteChartAfter" else 0), copiedChart)
    else:
        return "action = %s, ctx = %s, url = %s" % (action, ctx, url)
    if graphList:
        graphList = list(collections.OrderedDict.fromkeys(graphList))
        urlFields["graph"] = graphList
    url = URL(r=request, f='', vars=urlFields)
    redirect(url)

def DeleteDashboard():
    dashboardID = int(request.vars.dashboardID)
    sql = "DELETE FROM metric.dashboards WHERE dashboardID = %d" % dashboardID
    dbmetrics.executesql(sql)
    redirect("Dashboards")

#@cache(request.env.web2py_original_uri,time_expire=300,cache_model=cache.ram)
def FetchCondensedDashboardCollection():
    return FetchDashboardCollection()

def FetchDashboardCollection():
    collectionID = int(request.vars.collectionID)
    collection = GetCollection(collectionID)
    if not collection:
        return "Collection %s not found" % collectionID

    sql = "SELECT counterID FROM metric.collectionCounters WHERE collectionID = %d" % collectionID
    rows = dbmetrics.executesql(sql)
    for r in rows:
        ProcessAccessRules("COUNTER", r.counterID, subContent=True, embedded=True)

    lastDate = "'%s'" % MakeSafe(request.vars.dt)
    numDays = int(request.vars.numDays or 7)
    if not request.vars.dt or request.vars.dt == "None":
        lastDate = "NULL"
    return6To8 = 0
    calendar = 0
    if request.vars.periodType == "calendar" or collection.config.get("periodType", "latest") == "calendar":
        calendar = 1
    return6To8 = 1
    sql = "exec metric.CollectionDashboardView %d, %s, %s, %s, %s" % (collectionID, lastDate, numDays, return6To8, calendar)
    rows = dbmetrics.executesql(sql)
    numColumns = int(request.vars.numColumns or collection.config.get("dashboardNumColumns", 5))
    if not rows:
        return "No rows returned from %s" % sql
    filt = request.vars.filter
    if filt:
        try:
            filteredRows = []
            filt = filt.lower()
            for i, r in enumerate(rows):
                if filt in r.label.lower() or filt in r.counterName or filt in (r.subjectText or "").lower() or filt.lower() in (r.keyText or "").lower():
                    filteredRows.append(r)
            rows = filteredRows
        except:
            print "Error running filter", filt, collectionID
    return {
        "collection" : collection,
        "rows"       : rows,
        "numColumns" : numColumns,
        "numDaysForTrend" : numDays * numColumns + 7,
        "numDays"    : numDays,
    }

@cache(request.env.web2py_original_uri,time_expire=300,cache_model=cache.ram)
def EmbeddedDashboard():
    return Dashboard()

@FuncTime
def DashboardOld():
    dashboardID = int(request.vars.dashboardID or 0)
    dashboardName = ""
    collectionID = int(request.vars.collectionID or 0)
    dt = MakeSafe(request.vars.dt)
    groupID = 0
    groupName = ""
    numDays = 7
    collectionIDs = []
    if dashboardID:
        sql = "SELECT dashboardName, numDays, collections, groupID, groupName FROM metric.dashboardsEx WHERE dashboardID = %d" % int(request.vars.dashboardID)
        r = dbmetrics.executesql(sql)[0]
        if r.collections:
            collectionIDs = [int(i) for i in r.collections.split(",")]
        dashboardName = r.dashboardName
        numDays = r.numDays
        groupID = r.groupID
        groupName = r.groupName
    elif collectionID:
        collectionIDs = [collectionID]
        collection = GetCollection(collectionID)
        dashboardName = collection.collectionName
        groupID = collection.groupID
        groupName = collection.groupName

    groups = []
    numDays = int(request.vars.days or numDays)
    for collectionID in collectionIDs:
        lastDate = "NULL"
        if dt:
            lastDate = "'%s'" % dt
        sql = "exec metric.CollectionDashboardView %d, %s, %s" % (collectionID, lastDate, numDays)
        response.mainquery.append(sql)
        rows = dbmetrics.executesql(sql)
        collection = GetCollection(collectionID)
        groups.append([collection, rows])
    return {
        "groups"                : groups,
        "dashboardName"         : dashboardName,
        "counters"              : GetCounters(),
        "dashboardID"           : dashboardID,
        "collectionID"          : collectionID,
        "starred"               : IsStarred(TAG_DASHBOARD, dashboardID),
        "tags"                  : GetTagsForLink(TAG_DASHBOARD, dashboardID),
        "numDays"               : numDays,
        "groupID"               : groupID,
        "groupName"             : groupName,
        "dt"                    : dt,
        }

@FuncTime
def Dashboard():
    dashboardID = int(request.vars.dashboardID or 0)
    dashboardName = ""
    collectionID = int(request.vars.collectionID or 0)
    dt = MakeSafe(request.vars.dt)
    groupID = 0
    groupName = ""
    numDays = 7
    collectionIDs = []
    config = {}
    if dashboardID:
        ProcessAccessRules("DASHBOARD", dashboardID)
        sql = "SELECT dashboardName, numDays, collections, groupID, groupName, config FROM metric.dashboardsEx WHERE dashboardID = %d" % int(request.vars.dashboardID)
        try:
            r = dbmetrics.executesql(sql)[0]
        except IndexError:
            return "Dashboard %s does not exist" % request.vars.dashboardID
        if r.collections:
            collectionIDs = [int(i) for i in r.collections.split(",")]
        dashboardName = r.dashboardName
        numDays = r.numDays
        groupID = r.groupID
        groupName = r.groupName
        if r.config:
            config = json.loads(r.config)
    elif collectionID:
        ProcessAccessRules("COLLECTION", collectionID)
        collectionIDs = [collectionID]
        collection = GetCollection(collectionID)
        dashboardName = collection.collectionName
        groupID = collection.groupID
        groupName = collection.groupName

    groups = []
    numDays = int(request.vars.days or numDays)

    return {
        "collectionIDs"         : collectionIDs,
        "dashboardName"         : dashboardName,
        "counters"              : GetCounters(),
        "dashboardID"           : dashboardID,
        "collectionID"          : collectionID,
        "starred"               : IsStarred(TAG_DASHBOARD, dashboardID),
        "tags"                  : GetTagsForLink(TAG_DASHBOARD, dashboardID),
        "numDays"               : numDays,
        "groupID"               : groupID,
        "groupName"             : groupName,
        "dt"                    : dt,
        "config"                : config,
        }

def DashboardGraphs():
    dashboardID = int(request.vars.dashboardID or 0)
    collectionID = int(request.vars.collectionID or 0)
    collectionIDs = None
    dashboards = None
    dashboardName = "Unsaved dashboard"

    if dashboardID:
        sql = "SELECT dashboardName, collections FROM metric.dashboards WHERE dashboardID = %d" % dashboardID
        rows = dbmetrics.executesql(sql)
        collectionIDs = [int(i) for i in rows[0].collections.split(",")]
        dashboardName = rows[0].dashboardName
    elif collectionID:
        collectionIDs = collectionID
        if collectionIDs and type(collectionIDs) != type([]):
            collectionIDs = [collectionIDs]
        if not collectionIDs:
            collectionIDs = []
        collectionIDs = [int(c) for c in collectionIDs]


    return {
        "collectionIDs"         : collectionIDs,
        "collections"           : GetCollections(),
        "dashboards"            : GetDashboards(),
        "dashboardID"           : dashboardID,
        "dashboardName"         : dashboardName,
        "starred"               : IsStarred(TAG_DASHBOARD, dashboardID),
        }

def EmbeddedDashboardGraphs():
    return DashboardGraphs()

def EditDashboard():
    dashboardID = int(request.vars.dashboardID or 0)
    collectionIDs = []
    dashboardName = ""
    groupID = 0
    description = ""
    numDays = 7
    config = {}

    if dashboardID:
        sql = "SELECT dashboardName, description, groupID, numDays, collections, config FROM metric.dashboards WHERE dashboardID = %d" % dashboardID
        r = dbmetrics.executesql(sql)[0]
        collectionIDs = []
        if r.collections:
            collectionIDs = [int(i) for i in r.collections.split(",")]
        dashboardName = r.dashboardName
        description = r.description or ""
        groupID = r.groupID
        numDays = r.numDays
        if r.config:
            config = json.loads(r.config)

    return {
        "dashboardID"           : dashboardID,
        "dashboards"            : GetDashboards(),
        "collectionIDs"         : collectionIDs,
        "collections"           : GetCollections(),
        "dashboardName"         : dashboardName,
        "description"           : description,
        "groupID"               : groupID,
        "groups"                : GetGroups(),
        "numDays"               : numDays,
        "config"                : config,
    }

def SaveDashboard():
    collectionIDs = request.vars.collectionID
    dashboardName = MakeSafe(request.vars.dashboardName)
    description = MakeSafe(request.vars.description)
    groupID = int(request.vars.groupID)
    numDays = int(request.vars.numDays)
    config = {}
    config["numColumns"] = int(request.vars.numColumns)
    config["numDays"] = int(request.vars.numDays)
    config["reverse"] = 1 if request.vars.reverse else 0
    config["dayName"] = 1 if request.vars.dayName else 0
    config["ignoreZeros"] = 1 if request.vars.ignoreZeros else 0
    config["condensed"] = 1 if request.vars.condensed else 0
    config["justDot"] = 1 if request.vars.justDot else 0
    config["periodType"] = request.vars.periodType
    if collectionIDs and type(collectionIDs) != type([]):
        collectionIDs = [collectionIDs]
    if not collectionIDs:
        collectionIDs = []
    collectionIDs = ",".join(str(c) for c in collectionIDs)

    dashboardID = int(request.vars.dashboardID or 0)
    if dashboardID:
        sql = "UPDATE metric.dashboards SET dashboardName = '%s', description = '%s', groupID = %d, collections = '%s', numDays = %d, config = '%s' WHERE dashboardID = %d" % (dashboardName, description, groupID, collectionIDs, numDays, json.dumps(config).replace("'", "''"), dashboardID)
        dbmetrics.executesql(sql)
    else:
        sql = "INSERT INTO metric.dashboards (dashboardName, description, groupID, userName, numDays, collections, config) VALUES ('%s', '%s', %d, '%s', %d, '%s', '%s')" % (dashboardName, description, groupID, session.userName or "", numDays, collectionIDs, json.dumps(config).replace("'", "''"))
        dbmetrics.executesql(sql)
        sql = "SELECT TOP 1 dashboardID FROM metric.dashboards ORDER BY dashboardID DESC"
        dashboardID = dbmetrics.executesql(sql)[0][0]

    cache.ram("dashboards", None, 0) 
    redirect("Dashboard?dashboardID=%s" % dashboardID)

def SetWidth():
    if request.vars.fullwidth:
        v = int(request.vars.fullwidth)
    else:
        v = 0 if int(GetCookie("fullwidth") or 0) else 1

    SetCookie("fullwidth", v)

    redirect(request.env.http_referer)


# def MigrateCollections():
#     sql = "SELECT collectionID, aggregateMethod, normalize, annotations, startDate, endDate, isTable, numDays, zoom, viewMode, bargraph, interpolate, defaultView, timeDetails FROM collectionsExtra"
#     rows = dbmetrics.executesql(sql)
#     for r in rows:
#         cfg = {}
#         if r.aggregateMethod:
#             cfg["aggregateMethod"] = r.aggregateMethod
#         if r.normalize:
#             cfg["normalize"] = r.normalize
#         if r.annotations:
#             cfg["annotations"] = r.annotations
#         if r.startDate:
#             cfg["startDate"] = r.startDate
#         if r.endDate:
#             cfg["endDate"] = r.endDate
#         if r.isTable:
#             cfg["isTable"] = r.isTable
#         if r.numDays:
#             cfg["numDays"] = r.numDays
#         if r.zoom:
#             cfg["zoom"] = r.zoom
#         if r.viewMode:
#             cfg["viewMode"] = r.viewMode
#         if r.bargraph:
#             cfg["bargraph"] = r.bargraph
#         if r.interpolate:
#             cfg["interpolate"] = r.interpolate
#         if r.defaultView:
#             cfg["defaultView"] = r.defaultView
#         if r.timeDetails:
#             cfg["timeDetails"] = r.timeDetails
#         UpdateConfig("metric.collections", "collectionID=%s" % r.collectionID, cfg)


def DoCounters(persist=True):
    sql = "SELECT [value] FROM zsystem.settings WHERE [group] = 'metrics' AND [key] = 'Normalize'"
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    normalizeOptions = [["None", "None", 0, 0, 0]]
    try:
        lines = rows[0][0].split("\n")
        for l in lines:
            opt = [a.strip() for a in l.split(",")]
            for i in xrange(len(opt)):
                try:
                    opt[i] = int(opt[i])
                except:
                    pass

            normalizeOptions.append(opt)
    except:
        print "Could not load up normalization options from zsystem.settings: metrics.Normalize"

    if request.vars.w:
        graphWidth = int(request.vars.w)
        if persist: SetCookie("graph_width", graphWidth)
    else:
        graphWidth = GetCookie("graph_width") or 940
        graphWidth = 940 # disabling cookies

    if request.vars.h:
        graphHeight = int(request.vars.h)
        if persist: SetCookie("graph_height", graphHeight)
    else:
        graphHeight = GetCookie("graph_height") or None
        graphHeight = None # disabling cookies
    if int(GetCookie("fullwidth") or 0): graphWidth = "100%"
    txt = ""
    charts = []

    counterID = int(request.vars.counterID or 0)
    subjectID = int(request.vars.subjectID or 0)
    keyID = request.vars.keyID
    if keyID == "None" or keyID == "S":
        keyID = None
    else:
        keyID = int(keyID or 0)
    subjectText = keyText = ""
    subjectTitle = keyTitle = ""
    zoom = int(request.vars.zoom or 0)
    isBarGraph = int(request.vars.bargraph or 0)
    isInterpolate = int(request.vars.interpolate or 0)
    timeDetailsPeriod = None
    if request.vars.timedetails:
        timeDetailsPeriod = int(request.vars.timedetails)
    if request.vars.zoom is None:
        if request.vars.aggregateMethod:
            zoom = 0
    else:
        zoom = int(zoom)
    if request.vars.graph and type(request.vars.graph) == type(""):
        lst = request.vars.graph.split("_")
        counterID = int(lst[0])
        subjectID = keyID = None
        if len(lst) > 1:
            subjectID = int(lst[1])
        if len(lst) > 2:
            try:
                keyID = int(lst[2])
            except:
                keyID = lst[2]
    if counterID:
        subjectText, keyText = GetGraphText(counterID, subjectID, keyID)
        counter = GetCounterInfo(counterID)
        if not counter:
            return "Counter %s not found" % counterID
        subjectTitle = counter.subjectID
        keyTitle = counter.keyID

    # graph means that we have several graphs to show with Counters?graph=[counterID]_[subjectID]_[keyID]&...
    graphs = request.vars.graph
    collectionID = int(request.vars.collectionID or 0)
    collection = None
    collectionConfig = {}
    graphList = []
    h = 300

    aggregateMethod = "DateDay"
    normalize = ""
    startDate = ""
    endDate = ""
    numDays = 365
    annotations = "-2"
    isTable = False
    viewMode = "graphs"
    description = ""
    interval = 0
    isBarGraph = not not (int(request.vars.bargraph or 0))
    if graphs:
        if type(graphs) != types.ListType:
            graphs = [graphs]
        for g in graphs:
            l = g.split("_")
            subjectID = keyID = None
            if len(l) > 1:
                subjectID = int(l[1])
            if len(l) > 2:
                try:
                    keyID = int(l[2])
                except:
                    keyID = l[2]
            graphList.append([int(l[0]), subjectID, keyID, None])
    elif collectionID:
        collection = GetCollection(collectionID)
        if collection is None:
            return "Collection %s not found" % collectionID
        ProcessAccessRules("COLLECTION", collectionID)
        if collection.dynamicCounterID:
            redirect("Dashboard?collectionID=%s" % collectionID)
        collectionConfig = collection.config or {}
        description = collection.description
        aggregateMethod = collection.config.get("aggregateMethod", "DateDay")
        normalize = collection.config.get("normalize", 0)
        startDate = collection.config.get("startDate", None)
        endDate = collection.config.get("endDate", None)
        interval = collection.config.get("interval", 0)
        if collection.config.get("annotations", None) is not None:
            annotations = str(collection.config.get("annotations", None))
        isTable = collection.config.get("isTable", False) or False
        viewMode = collection.config.get("viewMode", viewMode)
        response.numViews = GetNumViewsForCounterOrCollection(collectionID=collectionID)
        if request.vars.zoom is None:
            zoom = int(collection.config.get("zoom", 0) or 0)
        if request.vars.bargraph is None:
            isBarGraph = int(collection.config.get("bargraph", 0) or 0)
        if request.vars.interpolate is None:
            isInterpolate = int(collection.config.get("interpolate", 0) or 0)
        if timeDetailsPeriod is None:
            timeDetailsPeriod = collection.config.get("timedetails", None)
        numDays = collection.config.get("numDays", None)
        for r in collection.counters or []:
            graphList.append([r.counterID, r.subjectID, r.keyID, r.collectionCounterID])
    else:
        graphList.append([counterID, subjectID, keyID, None])
    if collectionID:
        collection = GetCollection(collectionID)
    newGraphList = []
    for g in graphList:
        # top xx graphs
        if g[2] == "S":
            g[2] = None
        if g[2] is not None and g[2] < 0:
            # note that this will fail if we don't have data for the past 2 days

            subSql = ""
            if g[1] >= 0:
                subSql = "AND subjectID = %d " % g[1]
            if request.vars.search:
                s = request.vars.search.replace("'", "''")
                subSql = "AND (subjectText LIKE '%%%s%%' OR keyText LIKE '%%%s%%') " % (s, s)
#            sql = """
#                SELECT TOP %(num)s subjectID, keyID, SUM(value)
#                  FROM zmetric.dateCountersEx
#                 WHERE counterID = %(counterID)d %(sub)sAND counterDate >= GetUTCDate()-7
#                 GROUP BY subjectID, keyID
#                 ORDER BY 3 DESC
#            """ % {"num": -g[2], "counterID": g[0], "sub": subSql}
            sql = """
                SELECT TOP %(num)s subjectID = columnID, keyID, SUM(value)
                  FROM zmetric.keyCountersEx
                 WHERE counterID = %(counterID)d %(sub)sAND counterDate >= GetUTCDate()-7
                 GROUP BY columnID, keyID
                 ORDER BY 3 DESC
            """ % {"num": -g[2], "counterID": g[0], "sub": subSql}
            response.mainquery.append(sql)
            rows = dbmetrics.executesql(sql)
            for r in rows:
                newGraphList.append([g[0], r.subjectID, r.keyID, g[3]])
        else:
            newGraphList.append(g)
    graphList = newGraphList
    if graphHeight is None:
        graphHeight = h
    normalize = request.vars.normalize if request.vars.normalize is not None else normalize
    aggregateMethod = request.vars.aggregateMethod or aggregateMethod
    aggregateMethodRaw = aggregateMethod
    if request.vars.startDate is not None:
        startDate = request.vars.startDate
    if request.vars.endDate is not None:
        endDate = request.vars.endDate
    if request.vars.numDays is not None:
        numDays = request.vars.numDays or numDays
    numDays = int(numDays or 0)
    annotations = request.vars.annotations or annotations
    annotations = int(annotations or -2)
    isTable = request.vars.isTable if request.vars.isTable else isTable
    if isTable == "None": isTable = False
    isTable = int(isTable)
    viewMode = request.vars.viewMode if request.vars.viewMode else viewMode
    if not viewMode: viewMode = "graphs"
    div = 1
    onlySundays = ""
    numDaysPerPoint = 1
    aggregateMethodSql = aggregateMethod
    if aggregateMethod == "DateWeekByDay":
        aggregateMethodSql = "DateWeek"
        div = 7
        numDaysPerPoint = 7
    if aggregateMethod == "Sundays":
        aggregateMethodSql = "DateDay"
        div = 1
        onlySundays = "AND DATEPART(dw, counterDate) = 1"
        numDaysPerPoint = 7
    if aggregateMethod == "DateWeek":
        numDaysPerPoint = 7
    if aggregateMethod == "DateMonth":
        numDaysPerPoint = 30

    factorials = {}
    if normalize and not timeDetailsPeriod:
        normalizeCounterID = None
        for n in normalizeOptions:
            if normalize == n[0]:
                normalizeCounterID  = n[2]
                normalizeSubjectID  = n[3]
                normalizeKeyID      = n[4]
                break
        else:
            try:
                # check whether normalization is an explicit counter
                lst = [int(n) for n in normalize.split("_")]
                normalizeCounterID  = lst[0]
                normalizeSubjectID  = lst[1]
                normalizeKeyID      = lst[2]
            except:
                print "Invalid normalization option: ", normalize
        if normalizeCounterID is not None:
            sql = """EXEC metric.Counters_DateGraph %(counterID)s, %(subjectID)s, %(keyID)s, '%(aggregateMethod)s', %(days)s, %(startDate)s, %(endDate)s""" % {
                    "counterID"         : normalizeCounterID, 
                    "subjectID"         : normalizeSubjectID,
                    "keyID"             : normalizeKeyID,
                    "aggregateMethod"   : aggregateMethodRaw,
                    "days"              : SqlIntOrNULL(numDays),
                    "startDate"         : SqlStringOrNULL(startDate),
                    "endDate"           : SqlStringOrNULL(endDate),
                    }
            normRows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
            LogQuery(sql)
            for r in normRows:
                factorials[r[0]] = r[1]

    markers = []
    if annotations:
        #markers = GetMarkersByCategory(annotations)
        markers = GetMarkersForGraph(annotations)

    #
    # Get the actual chart data
    #

    TimeIt("go...")
    minValue = 9E20
    maxValue = -9E20
    firstDate = datetime.datetime.now()
    lastDate = firstDate - datetime.timedelta(days=1000)

    timeDetailsFound = False
    for i, g in enumerate(graphList):
        if not timeDetailsFound:
            sql = "SELECT TOP 1 counterDate FROM zmetric.keyTimeCounters WHERE counterID = %d" % g[0]
            rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
            if rows:
                timeDetailsFound = True
        configKey = "cfg%i_" % (i+1)
        config = {}
        for k, v in collectionConfig.iteritems():
            if k.startswith(configKey):
                config[k.replace(configKey, "")] = v
        for k in request.vars:
            if k.startswith(configKey):
                config[k.replace(configKey, "")] = getattr(request.vars, k)

        chart = GetCounterChart(g[0], g[1], g[2], g[3], startDate, endDate, numDays, aggregateMethod, factorials, markers, timeDetailsPeriod, config, viewMode)

        if chart:
            charts.append(chart)
        
        for s in chart["series"]:
            if s[1] < minValue: minValue = s[1]
            if s[1] > maxValue: maxValue = s[1]
            if s[0] < firstDate: firstDate = s[0]
            if s[0] > lastDate: lastDate = s[0]
    if not zoom:
        maxValue = minValue = None
    TimeIt("done!")

    allMarkerCategories = {}
    markerTypes = GetMarkerTypes()
    for typeID, markerType in markerTypes.iteritems():
        if typeID != 1: # just pick important dates for now
            continue
        allMarkerCategories[markerType.title] = []
        for categoryID, category in GetMarkerCategoriesForType(typeID).iteritems():
            allMarkerCategories[markerType.title].append(category)

    numCols = 4
    tags = None
    starred = False
    if collection:
        tags = GetTagsForLink(TAG_COLLECTION, collectionID)
        starred = IsStarred(TAG_COLLECTION, collectionID)

    response.numCharts = len(charts)
    isTable = (viewMode == "table")

    # now we combine all the data from the different charts into a single date index
    # this is used by the multigraph
    dataForDates = {}
    for c in charts:
        # find max value if we want to normalize
        mx = 1.0
        for v in c["data"]:
            if "norm" in viewMode and v > mx: mx = float(v)
        c["mult"] = mx

    #print "Date ranges: %s -> %s" % (firstDate, lastDate)
    dt = firstDate
    doneMarkers = set() # only add each marker once
    lastVals = collections.defaultdict(int)


    def FirstOfNextMonth(mydate):
        year, month = divmod(mydate.month+1, 12)
        if month == 0: 
              month = 12
              year = year -1
        next_month = datetime.datetime(mydate.year + year, month, 1)
        return next_month

    missingValuesByChart = collections.defaultdict(list)

    # minCount is used to zoom in stacked graphs because google chart doesn't support it and we need to do it by hand
    minCount, maxCount = None, None
    while dt <= lastDate:
        lst = []
        countForDate = 0
        for i in xrange(len(charts)):
            lst.append(0)
        for j, c in enumerate(charts):            
            lst[j] = 0
            for i, d in enumerate(c["dates"]):
                if d == dt:
                    lst[j] = c["data"][i] / c["mult"] # mult is 1.0 unless we want to normalize for multigraph
                    lastVals[j] = lst[j]
                    countForDate += lst[j]
                    break
            else:
                #print "No data on %s for %s" % (dt.date(), c["chartName"])
                if isInterpolate:
                    lst[j] = lastVals.get(j, 0)
                else:
                    missingValuesByChart[j].append((dt, lastVals.get(j, 0)))

        mk = ["", ""]
        for m in markers:
            if m.dateTime <= dt and m.dateTime > dt - datetime.timedelta(days=30) and m.dateTime not in doneMarkers:
                shortName = m.title[:12]
                fullName = "%s: %s - %s" % (FmtDate(m.dateTime), m.CATEGORY_TITLE, m.title)
                mk = [shortName, fullName]
                doneMarkers.add(m.dateTime)
        lst.insert(0, mk)
        dataForDates[dt] = lst

        if aggregateMethod == "DateMonth": # special case, always 1st of the month
            dt = FirstOfNextMonth(dt)
        else:
            dt += datetime.timedelta(days=numDaysPerPoint)

        if minCount is None or (countForDate > 0 and countForDate < minCount):
            minCount = countForDate
        if maxCount is None or (countForDate > 0 and countForDate > maxCount):
            maxCount = countForDate

    try:
        diff = 0.1 * (maxCount - minCount)
    except:
        diff = 1
        minCount = 0
        maxCount = 0
    minCount -= diff
    if not minCount: minCount = 0
    if not maxCount: maxCount = 0
    if not isInterpolate and request.vars.autointerpolate != "0":
        MAX_MISSING_VALUES_FOR_AUTO_INTERPOLATE = 5
        for chartIdx, vals in missingValuesByChart.iteritems():
            if len(vals) <= MAX_MISSING_VALUES_FOR_AUTO_INTERPOLATE:
                for v in vals:
                    #print dataForDates[v[0]][chartIdx+1]
                    dataForDates[v[0]][chartIdx+1] = v[1]
                    #print v[1]
            #print " %s: %s = %s" % (chartIdx, val[0], val[1])
    
    
    
    # TODO: make it work for stacked and aggregateMethod == "DateMonth"
    if "stacked" in viewMode and timeDetailsPeriod is None and aggregateMethod != "DateMonth":
        numdays = (lastDate - firstDate).days + 1    
        dateList = [ lastDate - datetime.timedelta(days=x) for x in range(0, numdays, numDaysPerPoint) ]
        
        for c in charts:
            for d in dateList:
                if d not in [seriesPoint[0] for seriesPoint in c["series"]]:
                    c["series"].append([d, 'null'])                                                
                    #print "added to %s : %s" % (c["chartName"], d)
            c["series"].sort(key=lambda dv: dv[0])
            c["dates"] = [item[0] for item in c["series"]]
            c["data"] = [item[1] for item in c["series"]]

    for c in charts:
        for dt, v in c["series"]:
            dtLst = str(dt).replace(" ", "-").replace(":", "-").split("-")
            hour = 0
            minute = 0
            try:
                hour = dtLst[3]
                minute = dtLst[4]
            except:
                pass
            c["seriesTxt"] += "[Date.UTC(%(year)d, %(month)d, %(day)d, %(hour)d, %(minute)d), %(val)s ],\n" % {
                    "year"  : int(dtLst[0]), 
                    "month" : int(dtLst[1])-1,
                    "day"   : int(dtLst[2]),
                    "hour"  : int(hour),
                    "minute"  : int(minute), 
                    "val"   : v,
                  }

    chartType = "AreaChart"
    if isBarGraph:
        chartType = "ColumnChart"
    #print "startDate", startDate
    #print "endDate", endDate
    #print "firstDate", firstDate
    #print "lastDate", lastDate
    return {
            "charts"       : charts, 
            "markers"      : markers, 
            "graphHeight"  : graphHeight,
            "graphWidth"   : graphWidth,
            "collection"   : collection,
            "normalize"    : normalize,
            "isTable"      : isTable,
            "aggregateMethod" : aggregateMethodRaw,
            "startDate"    : startDate,
            "endDate"      : endDate,
            "numDays"      : numDays,
            "annotations"  : annotations,
            "collections"  : GetCollections(),
            "allMarkersCategories" : allMarkerCategories,
            "tags"         : tags,
            "subjectText"  : subjectText,
            "keyText"      : keyText,
            "counterID"    : counterID,
            "subjectID"    : subjectID,
            "keyID"        : keyID,
            "subjectTitle" : subjectTitle,
            "keyTitle"     : keyTitle,
            "starred"      : starred,
            "zoom"         : zoom,
            "viewMode"     : viewMode,
            "isBarGraph"   : isBarGraph,
            "isInterpolate": isInterpolate,
            "timeDetailsPeriod": timeDetailsPeriod,
            "description"  : description,
            "dataForDates" : dataForDates,
            "chartType"    : chartType,
            "normalizeOptions" : normalizeOptions,
            "minCount"     : minCount,
            "minValue"     : minValue,
            "maxValue"     : maxValue,
            "firstDate"    : firstDate,
            "lastDate"     : lastDate,
            "timeDetailsFound" : timeDetailsFound,
        }


def GetCounterChart(counterID, subjectID, keyID, collectionCounterID, startDate, endDate, numDays, aggregateMethod, factorials, allMarkers, timeDetailsPeriod, config, viewMode):
    ProcessAccessRules("COUNTER", counterID, subContent=True)

    aggregateMethod = aggregateMethod or "DateDay"
    markers = []
    subjectText, keyText = GetGraphText(counterID, subjectID, keyID)
    counterInfo = GetCounterInfo(counterID)
    if counterInfo is None:
        return None
    counterName = counterInfo.counterName
    counterDescription = counterInfo.description
    comment = "%s / %s / %s" % (counterName, subjectText, keyText)
    dates = []
    div = 1
    pointSize = 0
    onlySundays = ""
    aggregateMethodRaw = aggregateMethod
    if aggregateMethod == "DateWeekByDay":
        if counterInfo.absoluteValue and 0:
            aggregateMethod = "DateDay"
        else:
            aggregateMethod = "DateWeek"
            div = 7
        
    if aggregateMethod == "Sundays":
        aggregateMethod = "DateDay"
        div = 1
        onlySundays = "AND DATEPART(dw, counterDate) = 1"
    dateRange = ""
    if startDate:
        dateRange += " AND counterDate >= '%s'" % startDate
    if endDate:
        dateRange += " AND counterDate <= '%s'" % endDate
    if numDays:
        # if we specify numDays we override the date range
        dateRange += " AND DateDiff(d, counterDate, GetUTCDate()) <= %d" % numDays
    keyAndSubject = keyAndColumn = ""
    if keyID is not None:
        keyAndSubject = "AND keyID = %s " % keyID
        keyAndColumn = "AND keyID = %s " % keyID
    if subjectID is not None:
        keyAndSubject += "AND subjectID = %s " % subjectID
        keyAndColumn += "AND columnID = %s " % subjectID
    rows = []
    yMult = float(config.get("yMult", 1.0) or 1.0)
    if timeDetailsPeriod is not None:
        sql = """EXEC metric.Counters_TimeGraph %(counterID)s, %(columnID)s, %(keyID)s, %(aggregateMinutes)s, %(days)s, %(startDate)s, %(endDate)s""" % {
            "counterID"         : counterID,
            "columnID"          : subjectID,
            "keyID"             : keyID,
            "aggregateMinutes"  : timeDetailsPeriod,
            "days"              : SqlIntOrNULL(numDays),
            "startDate"         : SqlStringOrNULL(startDate),
            "endDate"           : SqlStringOrNULL(endDate),
        }
        print sql
        response.mainquery.append(sql)
        try:
            rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
        except:
            rows = []
        #rows = dbmetrics.executesql(sql)
        interval = int(config.get("interval", 0) or 0)
        # if we have a specified interval we add zeroes in between
        if interval:
            newRows = []
            lastDate = None
            for r in rows:
                dt = datetime.datetime.strptime(r.DT, "%Y-%m-%d %H:%M:%S")
                while lastDate and dt - lastDate > datetime.timedelta(minutes=interval*2):
                    lastDate += datetime.timedelta(minutes=interval)
                    zeroRow = collections.namedtuple("DT", "VAL")
                    zeroRow.DT = lastDate.strftime("%Y-%m-%d %H:%M:%S")
                    zeroRow.VAL = 0
                    newRows.append(zeroRow)
                lastDate = dt
                newRows.append(r)
            rows = newRows
    if not rows:
        sql = """EXEC metric.Counters_DateGraph %(counterID)s, %(subjectID)s, %(keyID)s, '%(aggregateMethod)s', %(days)s, %(startDate)s, %(endDate)s""" % {
                "counterID"         : counterID, 
                "subjectID"         : subjectID,
                "keyID"             : keyID or 0,
                "aggregateMethod"   : aggregateMethodRaw,
                "days"              : SqlIntOrNULL(numDays),
                "startDate"         : SqlStringOrNULL(startDate),
                "endDate"           : SqlStringOrNULL(endDate),
                }
        #print sql
        response.mainquery.append(sql)
        rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)


    timeDetails = None
    lst = []
    doneMarkers = set()
    lastRow = None
    seriesTxt = ""
    series = []
    minValue = 9E20
    maxValue = -9E20
    for r in rows:
        #print r.DT, r.VAL
        dt = r.DT
        try:
            dt = datetime.datetime.strptime(str(dt), "%Y-%m-%d %H:%M:%S")#.replace(hour=0, minute=0, second=0)
        except:
            dt = datetime.datetime.strptime(str(dt), "%Y-%m-%d")
        dates.append(dt)
        v = vOrig = r.VAL
        if v < minValue: minValue = v
        if v > maxValue: maxValue = v
        lastRow = vOrig
        if factorials:
            if r[0] in factorials:
                v = yMult * v / (float(factorials.get(r[0], -1)) or 1.0)
            else:
                v = 0
        lst.append(v)
        mk = ["", "", 0]
        for m in (allMarkers or []):
            if m.dateTime <= dt and m.dateTime > dt - datetime.timedelta(days=30) and m.dateTime not in doneMarkers:
                shortName = m.title[:12]
                fullName = "%s: %s - %s" % (FmtDate(m.dateTime), m.CATEGORY_TITLE, m.title)
                mk = [shortName.replace("'", "\\'"), fullName.replace("'", "\\'"), m.markerID]
                doneMarkers.add(m.dateTime)
        markers.append(mk)

        dtLst = str(r.DT).replace(" ", "-").replace(":", "-").split("-")
        hour = 0
        minute = 0
        try:
            hour = dtLst[3]
            minute = dtLst[4]
        except:
            pass
        #v = r.VAL
        series.append((dt, v))

    # maybe remove the last point if it is invalid
    if aggregateMethod != "DateDay":
        doit = False

        if aggregateMethod == "DateMonth":
            if datetime.datetime.now()-dates[-1] < datetime.timedelta(days=30):
                doit = True
        elif aggregateMethod == "DateWeek" and dates:
            if datetime.datetime.now()-dates[-1] < datetime.timedelta(days=7):
                doit = True
        if doit and len(dates) > 2:
            dates = dates[:-1]
            lst = lst[:-1]

    allData = lst

    #counterName = A(counterName, _href=("Report?counterID=%s" % counterID))
    #chartName = "%s" % (counterName)
    chartName = ""
    if subjectText and keyText:
        chartName = "%s - %s" % (subjectText, keyText)
    elif subjectText:
        chartName = "%s" % (subjectText)
    elif keyText:
        chartName = "%s" % (keyText)
    try:
        chartName = str(XML(chartName.encode("UTF-8", errors="ignore")))
    except Exception, e:
        chartName = "Error: %s" % e

    chart = {
        "controlID" : "counter_%s_%s_%s" % (counterID, subjectID, keyID),
        "chartName" : chartName,
        "counterID" : counterID,
        "counterName" : counterName,
        "data"      : allData,
        "dates"     : dates,
        "counterDescription" : counterDescription,
        "groupID"   : counterInfo.groupID,
        "groupName" : counterInfo.groupName,
        "absoluteValue" : counterInfo.absoluteValue,
        "subjectID" : subjectID,
        "keyID"     : keyID,
        "markers"   : markers,
        "pointSize" : pointSize,
        "collectionCounterID" : collectionCounterID,
        "timeDetails" : timeDetails,
        "series"    : series,
        "seriesTxt" : seriesTxt,
        "minValue"  : minValue,
        "maxValue"  : maxValue,
        "config"    : config,
    }
    return chart


def TimeCounters():
    def InsertFudgePoints(series):
        ret = []
        #datetime.datetime.strptime(r.counterDate, "%Y-%m-%d %H:%M:%S")
        lastDT = None
        for i, s in enumerate(series):
            dt = datetime.datetime.strptime(s[0], "%Y-%m-%d %H:%M:%S")
            if lastDT:
                pass#print dt-lastDT
            lastDT = dt
        return series

    yesterday = FmtDate(datetime.datetime.now() - datetime.timedelta(days=1))
    startDate = (request.vars.startDate or yesterday)
    endDate   = (request.vars.endDate or yesterday)
    graphs = request.vars.graph
    # we will support multiple graphs later
    dtStart = datetime.datetime.strptime(startDate, "%Y-%m-%d")
    dtEnd = datetime.datetime.strptime(endDate, "%Y-%m-%d")
    delta = datetime.timedelta(days=1)

    nextDayUrl = prevDayUrl = GetFullUrlWithout("startDate&endDate")
    prevDayUrl += "startDate=%s&endDate=%s" % (FmtDate(dtStart - delta), FmtDate(dtEnd - delta))
    nextDayUrl += "startDate=%s&endDate=%s" % (FmtDate(dtStart + delta), FmtDate(dtEnd + delta))

    if isinstance(graphs, str):
        graphs = [graphs]

    for g in graphs:
        counterID, columnID, keyID = tuple([int(c) for c in g.split("_")])
        sql = """SELECT counterDate, value
                   FROM zmetric.keyTimeCounters
                  WHERE counterID = %(counterID)s AND columnID = %(columnID)s AND keyID = %(keyID)s AND counterDate BETWEEN '%(startDate)s' AND DateAdd(d, 1, '%(endDate)s')
                  ORDER BY counterDate ASC""" % {"counterID" : counterID, "columnID" : columnID, "keyID" : keyID, "startDate" : startDate, "endDate" : endDate}
        response.mainquery.append(sql)
        rows = dbmetrics.executesql(sql)
        series = []
        for r in rows:
            s = (r.counterDate, r.value)
            series.append(s)
        series = InsertFudgePoints(series)
        counterInfo = GetCounterInfo(counterID)
        subjectText, keyText = GetGraphText(counterID, columnID, keyID)
        return {
            "rows" : rows, 
            "counterInfo": counterInfo, 
            "subjectName" : subjectText,
            "prevDayUrl" : prevDayUrl,
            "nextDayUrl" : nextDayUrl,
            "startDate" : startDate,
            "endDate" : endDate,
            "series" : series,
            }

#
# Reports
#

currTime = None
def TimeIt(mrk):
    t = datetime.datetime.now()


def GetTagsForEntity(linkType):
    sql = """
     SELECT linkID, tagName, userName
       FROM tagLinks l
       INNER JOIN tags t ON t.tagID = l.tagID
      WHERE t.tagName != 'STARRED' AND l.linkType = %s
      ORDER BY linkID
    """ % linkType
    LogQuery(sql)
    tagRows = dbmetrics.executesql(sql)
    tags = {}
    for r in tagRows:
        if r.linkID not in tags:
            tags[r.linkID] = []
        tags[r.linkID].append((r.tagName, r.userName))
    return tags

@FuncTime
def Groups():
    response.title = "%s - Groups" % SITE_TITLE
    sql = """
        SELECT g.groupID, g.groupName, num=COUNT(*)
          FROM zmetric.groups g
            INNER JOIN metric.dashboards c ON c.groupID = g.groupID
        GROUP BY g.groupID, g.groupName
        ORDER BY g.groupName ASC
    """
    dashboardGroups = dbmetrics.executesql(sql)
    sql = """
        SELECT g.groupID, g.groupName, num=COUNT(*)
          FROM zmetric.groups g
            INNER JOIN zmetric.counters c ON c.groupID = g.groupID
        WHERE c.hidden = 0
        GROUP BY g.groupID, g.groupName
        ORDER BY g.groupName ASC
    """
    reportGroups = dbmetrics.executesql(sql)
    sql = """
        SELECT g.groupID, g.groupName, num=COUNT(*)
          FROM zmetric.groups g
            INNER JOIN metric.collections c ON c.groupID = g.groupID
        --WHERE c.hidden = 0
        GROUP BY g.groupID, g.groupName
        ORDER BY g.groupName ASC
    """
    collectionGroups = dbmetrics.executesql(sql)
    return {
        "dashboardGroups"   : dashboardGroups,
        "reportGroups"      : reportGroups,
        "collectionGroups"  : collectionGroups,
        }


def CreateFilterList(rows, tag):
    groups = collections.OrderedDict()
    allTags = GetTagsForEntity(tag)
    foundTags = set()
    lastGroupID = None
    for r in rows:
        for t in allTags.get(r.entityID, []):
            if t[0]: foundTags.add(t[0])

        k = (r.groupID, r.groupName, tag)
        if k not in groups:
            groups[k] = []

        groups[k].append(r)
    foundTags = list(foundTags)
    foundTags.sort()
    return {
        "groups"        : groups,
        "tags"          : allTags,
        "foundTags"     : foundTags,
        "tagType"       : tag,
        }

@FuncTime
def Reports():
    response.title = "%s - Reports" % SITE_TITLE
    if request.vars.counterID:
        redirect("Report?counterID=%s" % request.vars.counterID)

    mr = ""
    if request.vars.groupID:
        mr = " AND groupID = %d" % int(request.vars.groupID)
    sql = """
        SELECT restricted=0, entityID=counterID, name=counterName, counterID, counterName, description=description + '<br><i>' + counterIdentifier + '</i>' collate database_default, groupID, groupName, parentID=parentCounterID, modifyDate, createDate, userName, published
          FROM zmetric.countersEx WHERE hidden = 0 AND obsolete = 0%s
         ORDER BY groupOrder, groupName, [order], counterName ASC
    """ % mr
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        r.restricted = IsRestricted("COUNTER", r.entityID)
    return CreateFilterList(rows, TAG_REPORT)


@FuncTime
def Collections():
    if request.vars.collectionID:
        collectionID = int(request.vars.collectionID)
        collection = GetCollection(collectionID)
        if collection.config.get("defaultView", "graphs") == "dashboard":
            redirect("Dashboard?collectionID=%d" % collectionID)
        else:
            redirect("Counters?collectionID=%d" % collectionID)

    response.title = "%s - Collections" % SITE_TITLE

    mr = ""
    if request.vars.groupID:
        mr = " WHERE c.groupID = %d" % int(request.vars.groupID)
    sql = """
    SELECT DISTINCT restricted=0, entityID=c.collectionID, name=c.collectionName, c.collectionID, c.createDate, c.collectionName, c.description, c.groupID, parentID=NULL, c.userName, ISNULL(g.[order], 9999), groupName=ISNULL(g.groupName, 'unknown'), c.[order]
      FROM metric.collections c
        LEFT JOIN zmetric.groups g ON g.groupID = c.groupID
     %s
     ORDER BY ISNULL(g.[order], 9999), ISNULL(g.groupName, 'unknown'), c.[order], collectionName ASC
    """ % mr
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        r.restricted = IsRestricted("COLLECTION", r.entityID)
    return CreateFilterList(rows, TAG_COLLECTION)     

@FuncTime
def Dashboards():
    response.title = "%s - Dashboards" % SITE_TITLE

    mr = ""
    groupID = request.vars.groupID
    if groupID:
        if groupID == "None":
            groupID = 0

        mr = " WHERE ISNULL(d.groupID, 0) = %d" % int(groupID)
    sql = """
    SELECT restricted=0, entityID=d.dashboardID, name=d.dashboardName, d.dashboardID, d.dashboardName, d.createDate, d.description, d.groupID, g.[order], groupName=ISNULL(g.groupName, 'unknown'), g.[order], d.userName
      FROM metric.dashboards d
        LEFT JOIN zmetric.groups g ON g.groupID = d.groupID
     %s
     ORDER BY ISNULL(g.[order], 9999), ISNULL(g.groupName, 'unknown'), d.dashboardName ASC
    """ % mr
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        r.restricted = IsRestricted("DASHBOARD", r.entityID)
    return CreateFilterList(rows, TAG_DASHBOARD)

def Test():
    return "OK"

def EditDescription():
    tableName = "zmetric.counters"
    columnName = "counterID"
    rowID = request.vars.counterID
    if not rowID:
        tableName = "metric.collections"
        columnName = "collectionID"
        rowID = request.vars.collectionID
        cache.ram("collections", None, 0)
    else:
        cache.ram("counter_%s" % rowID, None, 0) 
    rowID = int(rowID)
    desc = request.vars.descedit.replace("'", "''")
    sql = "UPDATE %s SET description = '%s' WHERE %s = %d" % (tableName, desc, columnName, rowID)
    dbmetrics.executesql(sql)
    cache.ram("counterinfo", None, 0)
    
    txt = """
    <script>
    window.parent.document.getElementById("desc").innerHTML = '%s';
    </script>
    """ % FmtText2(request.vars.descedit or "").replace("'", "\\'").replace("\r", "")
    return XML(txt)

def EmbeddedReport():
    return Report()

@FuncTime
def Report():
    startTime = time.time()

    def PRINTTIME(timeCnt):
        print "### TIME %s. %.3f" % (timeCnt, time.time()-startTime)
    try:
        counterID = int(request.vars.counterID or 0)
        if not GetCounterInfo(counterID):
            return "Counter %s not found" % counterID
    except Exception:
        sql = "SELECT counterID FROM zmetric.counters WHERE counterIdentifier = '%s'" % MakeSafe(request.vars.counterID)
        LogQuery(sql)
        rows = dbmetrics.executesql(sql)
        if not rows:
            return "Counter not found"
        counterID = rows[0].counterID
        redirect(GetFullUrlWithout("counterID") + "counterID=%s" % counterID)

    c = GetCounterInfo(counterID)

    ProcessAccessRules("COUNTER", int(request.vars.counterID), c.userName)

    reports = []
    numDays = int(request.vars.numDays or 1)
    dt = FmtDate(datetime.datetime.now() - datetime.timedelta(days=1))
    extratxt = ""
    #PRINTTIME(1)

    if request.vars.dt:
        dt = request.vars.dt
    else:
        # no date specified, find the most recent one
        sql = "EXEC zmetric.Counters_ReportDates %d" % counterID
        rows = dbmetrics.executesql(sql)
        if rows:
            dt = rows[0].dateReturned
            #extratxt = " <font size=-1>(Most recent report)</font>"
    #PRINTTIME(2)

    dt = datetime.datetime.strptime(dt, "%Y-%m-%d")
    startDate = dt - datetime.timedelta(days=numDays-1)
    prevDate = dt + datetime.timedelta(days=-numDays)
    nextDate = dt + datetime.timedelta(days=numDays)
    prevLink = A(XML("&larr; Older"), _href=GetFullUrlWithout("dt") + "dt=%s" % (FmtDate(prevDate)))
    nextLink = A(XML("Newer &rarr;"), _href=GetFullUrlWithout("dt") + "dt=%s" % (FmtDate(nextDate)))
    navLinks = "%s &middot; %s" % (prevLink, nextLink)
    # find columns
    #print "*"*80
    #PRINTTIME(3)

    #PRINTTIME(4)
    sql = "select OBJECT_DEFINITION(OBJECT_ID('%s'))" % c.procedureName
    procText = dbmetrics.executesql(sql)[0][0]
    keyLink = subjectLink = ""
    keyLabel = subjectLabel = ""

    #PRINTTIME(5)

    subjectLookupTableID = c.subjectLookupTableID
    keyLookupTableID = c.keyLookupTableID
    if subjectLookupTableID:
        l = GetLookupTable(subjectLookupTableID)
        subjectLink = l.link
        subjectLabel = l.label
    if keyLookupTableID:
        l = GetLookupTable(keyLookupTableID)
        keyLink = l.link
        keyLabel = l.label
    subjectTitle = c.subjectID
    keyTitle = c.keyID
    reportName = c.counterName
    groupName = c.groupName
    groupID = c.groupID
    allRows = []
    if request.vars.all:
        sql = """
             SELECT subjectID=lookupID, keyID=NULL, subjectText=ISNULL(fullText, lookupText), keyText=''
               FROM zsystem.lookupValuesEx v1
                 LEFT JOIN zmetric.counters c ON c.subjectLookupTableID = v1.lookupTableID
              WHERE c.counterID = %(c)s AND (fullText LIKE '%%%(s)s%%' OR lookupText LIKE '%%%(s)s%%')
            UNION
             SELECT subjectID=NULL, keyID=lookupID, subjectText='', keyText=ISNULL(fullText, lookupText)
               FROM zsystem.lookupValuesEx v
                 LEFT JOIN zmetric.counters c ON c.keyLookupTableID = v.lookupTableID
              WHERE c.counterID = %(c)s AND (fullText LIKE '%%%(s)s%%' OR lookupText LIKE '%%%(s)s%%')
        """ % {"s": MakeSafe(request.vars.filterText), "c" : counterID}
        response.mainquery.append(sql)
        allRows = dbmetrics.executesql(sql)

    #PRINTTIME(6)
    keyColumns = collections.OrderedDict()
    if subjectLookupTableID:
        keyColumns["subjectID"] = subjectTitle
        keyColumns["subjectTitle"] = subjectTitle.replace("ID", "")
    if keyTitle:
        keyColumns["keyID"] = keyTitle
        keyColumns["keyTitle"] = keyTitle.replace("ID", "")

    report = GetReportData(counterID, startDate, dt)

    numCols = len(report["columns"]) + len(keyColumns)

    maxRows = 20 if not request.vars.maxRows else int(request.vars.maxRows)

    reportTitle = "%s on %s%s" % (reportName, FmtDate(dt), extratxt)
    reportDescription = c.description

    tags = GetTagsForLink(TAG_REPORT, counterID)
    response.numViews = GetNumViewsForCounterOrCollection(counterID=counterID)
    groupText = ""
    #PRINTTIME(7)
    sql = "SELECT counterID, counterName, parentCounterID FROM zmetric.countersEx WHERE groupID = %d ORDER BY parentCounterID, [order]" % (groupID or 0)
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    #PRINTTIME(8)
    for r in rows:
        m = ""
        if r.parentCounterID:
            m = "&nbsp;&nbsp;&nbsp;"
        groupText += "%s<a href=\"%scounterID=%d\">%s</a><br>" % (m, GetFullUrlWithout("counterID"), r.counterID, r.counterName)
    groupText = XML(groupText)
    response.procquery = [procText]
    response.title = "%s" % reportName
    relatedCounters = {}
    #PRINTTIME(9)
    sql = "SELECT * FROM zmetric.counters WHERE counterID <> %s and ((source <> '' AND Lower(source) LIKE '%s') OR (procedureName <> '' AND Lower(procedureName) LIKE '%s'))" % (counterID, (c.source or "").lower(), (c.procedureName or "").lower())
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    for r in rows:
        inf = GetCounterInfo(r.counterID)
        relatedCounters[inf.counterName] = inf
    #PRINTTIME(10)

    return {
        "counterID"   : counterID,
        "reportTitle" : reportName,
        "reportDate"  : dt,
        "groupName" : groupName,
        "groupID" : groupID,
        "description" : reportDescription,
        "navigationLinks" : navLinks,
        "report"     : report,
        "menu"       : None,
        "collections": GetCollections(),
        "tags"       : tags,
        "numCols"     : numCols,
        "keyTitle"   : keyTitle,
        "subjectTitle" : subjectTitle,
        "starred"    : IsStarred(TAG_REPORT, counterID),
        "keyLink"    : keyLink,
        "subjectLink": subjectLink,
        "keyLabel"   : keyLabel,
        "subjectLabel": subjectLabel,
        "groupText"  : groupText,
        "numDays"    : numDays,
        "counter"    : c,
        "relatedCounters" : relatedCounters,
        "keyColumns" : keyColumns,
        }


def GetNumViewsForCounterOrCollection(counterID=None, collectionID=None):
    n = "collectionID"
    if counterID: n = "counterID"
    sql = "SELECT COUNT(*) FROM pageViews WHERE %s=%d" % (n, counterID or collectionID)
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    return int(rows[0][0])


def MakeProcTextForCounter(c):
    stmt = ""
    if c.subjectID:
        stmt = """
  INSERT INTO zmetric.dateCounters (counterID, counterDate, subjectID, keyID, value)
  SELECT @counterID, @counterDate, %(subjectID)s, %(keyID)s, COUNT(*)
    FROM ebs_RESEARCH.%(source)s
   WHERE eventID BETWEEN @fromID AND @toID
   GROUP BY [keyLookupTableName]
        """ % {"source": c.source, "keyID": c.keyID, "subjectID": c.subjectID}
    elif c.keyID:
        stmt = """
  INSERT INTO zmetric.dateCounters (counterID, counterDate, subjectID, keyID, value)
  SELECT @counterID, @counterDate, 0, %(keyID)s, COUNT(*)
    FROM ebs_RESEARCH.%(source)s
   WHERE eventID BETWEEN @fromID AND @toID
   GROUP BY %(keyID)s
        """ % {"source": c.source, "keyID": c.keyID}
    else:
        subjects = GetCounterSubjects(c.counterID)
        for s in subjects:
            stmt += """
  -- Add to column: %(name)s
  INSERT INTO zmetric.dateCounters (counterID, counterDate, subjectID, keyID, value)
  SELECT @counterID, @counterDate, %(subjectID)s, 0, COUNT(*)
    FROM ebs_RESEARCH.%(source)s
   WHERE eventID BETWEEN @fromID AND @toID
   GROUP BY %(subjectID)s
            """ % {"source": c.source, "subjectID": s.lookupID, "name": s.lookupText}
    txt = """
CREATE PROCEDURE %(procName)s
  @counterDate  date = NULL
AS
  DECLARE @fromID bigint, @toID bigint

  DECLARE @counterID smallint
  SET @counterID = zmetric.Counters_ID('%(counterIdentifier)s')

  EXEC metric.GetDates @counterDate OUTPUT
  EXEC metric.GetIdentities '%(source)s', @counterDate, @fromID OUTPUT, @toID OUTPUT
  IF @fromID < 0 OR @toID < 0 RETURN

  -- Write a comment explaining what you are counting here%(stmt)s
GO

    """ % {"procName": c.procedureName, "stmt": stmt, "source": c.source, "counterIdentifier": c.counterIdentifier}
    return txt

@FuncTime
def ViewProc():
    response.title = "%s - View Proceedure" % SITE_TITLE
    c = GetCounterInfo(int(request.vars.counterID))
    sql = "select OBJECT_DEFINITION(OBJECT_ID('%s'))" % c.procedureName
    procText = dbmetrics.executesql(sql)[0][0]
    txt = ""
    if procText is None:
        txt = "The procedure %s does not exist. Here is some helpful boilerplate to create it<br><br>" % c.procedureName
        procText = MakeProcTextForCounter(c)
    txt += "<pre class=sh_sql>%s</pre><br>" % procText
    return {"txt": XML(txt)}


@FuncTime
def UpdateCollection(collectionID):
    sd = request.vars.startDate
    if sd:
        sd = "'%s'" % sd
    ed = request.vars.endDate
    if ed:
        ed = "'%s'" % ed
    a = request.vars.aggregateMethod
    n = request.vars.normalize
    an = request.vars.annotations
    timedetails = "NULL"
    # 'global' configs
    configChanges = {
        "aggregateMethod"   : request.vars.aggregateMethod,
        "normalize"         : request.vars.normalize,
        "annotations"       : request.vars.annotations,
        "startDate"         : request.vars.startDate,
        "endDate"           : request.vars.endDate,
        "isTable"           : request.vars.isTable,
        "numDays"           : request.vars.numDays,
        "zoom"              : request.vars.zoom,
        "bargraph"          : request.vars.bargraph,
        "interpolate"       : request.vars.interpolate,
        "viewMode"          : request.vars.viewMode,
        "timedetails"       : request.vars.timedetails,
        }

    # per-chart configs
    for v in request.vars:
        if v.startswith("cfg"):
            # get rid of cfg without a number (which is the base form)
            n = v.replace("cfg", "").split("_")[0]
            try:
                n = int(n)
                configChanges[v] = request.vars[v]
            except:
                pass

    UpdateConfig("metric.collections", "collectionID=%s" % collectionID, configChanges)

    # if there are any explicit graphs we override the ones in the collection
    if request.vars.graph:
        graphs = request.vars.graph
        if isinstance(graphs, str):
            graphs = [graphs]
        sql = "SELECT collectionCounterID, counterID, subjectID, keyID, collectionIndex FROM metric.collectionCounters WHERE collectionID = %d ORDER BY collectionIndex ASC" % collectionID
        LogQuery(sql)
        rows = dbmetrics.executesql(sql)
        graphsInDB = []
        for r in rows:
            g = "%s_%s_%s" % (r.counterID, r.subjectID, r.keyID)
            graphsInDB.append(g)
        #return "%s <br><br>vs.<br><br> %s" % (graphsInDB, graphs)
        # remove graphs from DB that are not passed in
        for g in graphsInDB:
            if g not in graphs:
                counterID, subjectID, keyID = tuple([int(c) for c in g.split("_")])
                sql = "DELETE FROM metric.collectionCounters WHERE collectionID = %d AND counterID = %d AND subjectID = %d AND keyID = %d" % (collectionID, counterID, subjectID, keyID)
                LogQuery(sql)
                dbmetrics.executesql(sql)
        # add graphs into DB that were not there before but were passed in
        for g in graphs:
            if g not in graphsInDB:
                counterID, subjectID, keyID = tuple([int(c) for c in g.split("_")])
                sql = """
                    INSERT INTO metric.collectionCounters (collectionID, collectionIndex, counterID, subjectID, keyID, config)
                    VALUES (%s, 0, %s, %s, %s, '%s')
                """ % (collectionID, counterID, subjectID, keyID, "")
                LogQuery(sql)
                dbmetrics.executesql(sql)
        # now order the graphs in the DB according to the ordering that was passed in
        if graphs != graphsInDB:
            for i, g in enumerate(graphs):
                counterID, subjectID, keyID = tuple([int(c) for c in g.split("_")])
                sql = "UPDATE metric.collectionCounters SET collectionIndex = %d WHERE collectionID = %d AND counterID = %d AND subjectID = %d AND keyID = %d" % (i+1, collectionID, counterID, subjectID, keyID)
                LogQuery(sql)
                dbmetrics.executesql(sql)

    cache.ram("collections", None, 0)


def AddNewToCollection():
    collectionID = request.vars.collectionID
    name = MakeSafe(request.vars.collectionName)
    collectionID = int(collectionID)
    newCollection = False
    if collectionID <= 0:
        newCollection = True
        collectionID = CreateCollection(name)

    counters = request.vars.graph
    if not counters:
        counters = ["%s_%s_%s" % (request.vars.counterID, request.vars.subjectID, request.vars.keyID)]
    if type(counters) != types.ListType:
        counters = [counters]
    for counter in counters:
        lst = counter.split("_")
        subjects = str(lst[1]).split(",")
        for s in subjects:
            AddCounterToCollection(collectionID, lst[0], s, lst[2] if len(lst) > 2 else None)

    cache.ram("collections", None, 0) 

    return collectionID

@FuncTime
def AddToCollection():
    collectionID = request.vars.collectionID
    name = MakeSafe(request.vars.name)
    if collectionID == "":
        redirect(request.env.http_referer)
        return
    collectionID = int(collectionID)
    # if collectionID is 0 we make a new one
    newCollection = False
    if collectionID <= 0:
        newCollection = True
        collectionID = CreateCollection(name)

    counters = request.vars.counter
    if type(counters) != types.ListType:
        counters = [counters]
    for counter in counters:
        lst = counter.split("_")
        subjects = str(lst[1]).split(",")
        for s in subjects:
            AddCounterToCollection(collectionID, lst[0], s, lst[2] if len(lst) > 2 else None)

    cache.ram("collections", None, 0) 

    if newCollection:
        redirect("EditCollection?collectionID=%s&new=1" % collectionID)
    else:
        redirect("Counters?collectionID=%s" % collectionID)

def AddCounterToCollection(collectionID, counterID, subjectID, keyID):
    subjectID if subjectID is not None else "NULL"
    keyID = keyID if keyID is not None and keyID is not "S" else "NULL"
    idx = GetTopCollectionCounterIndex(collectionID)+1
    sql = """SELECT * FROM metric.collectionCounters WHERE collectionID = %s AND counterID = %s AND subjectID = %s AND keyID = %s
    """ % (collectionID, counterID, subjectID, keyID)
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    if rows:
        return
    sql = """
        INSERT INTO metric.collectionCounters (collectionID, collectionIndex, counterID, subjectID, keyID)
        VALUES (%s, %s, %s, %s, %s)
    """ % (collectionID, idx, counterID, subjectID, keyID)
    LogQuery(sql)
    dbmetrics.executesql(sql)

    cache.ram("collections", None, 0) 


@FuncTime
def RemoveFromCollection():
    sql = """
        DELETE
          FROM metric.collectionCounters
         WHERE collectionCounterID = %d
        """ % int(request.vars.collectionCounterID)
    LogQuery(sql)
    dbmetrics.executesql(sql)

    cache.ram("collections", None, 0) 

    redirect(request.env.http_referer)


@FuncTime
def DeleteCollection():
    LoggedIn()

    collectionID = int(request.vars.collectionID)
    sql = "EXEC metric.Collections_Delete %d" % collectionID
    dbmetrics.executesql(sql)

    sql = """
        DELETE
          FROM tagLinks
         WHERE linkID = %s AND linkType = %s
        """ % (collectionID, TAG_COLLECTION)
    dbmetrics.executesql(sql)

    cache.ram("collections", None, 0) 

    redirect("Collections")


@FuncTime
def ClearCache():
    cache.ram.clear()
    redirect("Admin?message=Cache has been cleared")

@FuncTime
def CopyCollection():
    LoggedIn()
    collectionID = int(request.vars.collectionID or 0)
    if collectionID <= 0:
        return
    sql = """
INSERT INTO metric.collections (collectionName, groupID, [description], [order], dynamicCounterID, dynamicSubjectID, dynamicAggregateFunction, dynamicCount, config, userName)
  SELECT collectionName + ' (copy)', groupID, [description], [order], dynamicCounterID, dynamicSubjectID, dynamicAggregateFunction, dynamicCount, config, userName FROM metric.collections WHERE collectionID = %s
    """ % collectionID
    dbmetrics.executesql(sql)
    newCollectionID = GetTopCollectionID()

    sql = """
INSERT INTO metric.collectionCounters (collectionID, collectionIndex, counterID, subjectID, keyID, label, aggregateFunction, severityThreshold, goal, goalType, goalDirection, config)
  SELECT %s, collectionIndex, counterID, subjectID, keyID, label, aggregateFunction, severityThreshold, goal, goalType, goalDirection, config FROM metric.collectionCounters WHERE collectionID = %s
    """ % (newCollectionID, collectionID)
    dbmetrics.executesql(sql)
    redirect("/EditCollection?collectionID=%s" % newCollectionID)

def UpdateConfig(tableName, rowMatch, configChange):
    sql = "SELECT config FROM %s WHERE %s" % (tableName, rowMatch)
    configJson = dbmetrics.executesql(sql)[0].config
    if not configJson:
        config = {}
    else:
        config = json.loads(configJson)
    config = dict(config.items() + configChange.items())
    #print "new config: ", config
    configJson = json.dumps(config).replace("'", "''")
    sql = "UPDATE %s SET config='%s' WHERE %s" % (tableName, configJson, rowMatch)
    dbmetrics.executesql(sql)

def DeleteFromConfig(tableName, rowMatch, keys):
    sql = "SELECT config FROM %s WHERE %s" % (tableName, rowMatch)
    configJson = dbmetrics.executesql(sql)[0].config
    if not configJson:
        config = {}
    else:
        config = json.loads(configJson)
    for k in keys:
        try:
            del config[k]
        except:
            pass
    configJson = json.dumps(config).replace("'", "''")
    sql = "UPDATE %s SET config='%s' WHERE %s" % (tableName, configJson, rowMatch)
    dbmetrics.executesql(sql)

@FuncTime
def EditCollection():
    LoggedIn()
    if request.post_vars:
        v = request.post_vars        
        name = MakeSafe(v.name)
        description = MakeSafe(v.description)
        groupID = int(v.groupID)
        collectionID = int(v.collectionID)
        defaultView = MakeSafe(v.defaultView)
        dynamicCounterID = None
        dynamicSubjectID = None
        dynamicAggregateFunction = None
        dynamicCount = None
        collectionType = v.collectionType
        delKeys = []
        config = {
            "defaultView": defaultView,
            }
        for k in ["dashboardNumColumns", "dashboardArrow", "dashboardHistory", "periodType"]:
            val = getattr(v, k)
            if val == "default":
                delKeys.append(k)
            else:
                config[k] = val

        if delKeys:
            DeleteFromConfig("metric.collections", "collectionID=%s" % collectionID, delKeys)

        if collectionType == "dynamic":
            try:
                dynamicCounterID = int(v.dynamicCounterID)
                dynamicSubjectID = int(v.dynamicSubjectID)
                dynamicAggregateFunction = v.dynamicAggregateFunction
                dynamicCount = int(v.dynamicCount)
            except:
                return "Please fill in all dynamic attributes"
        if not name:
            return "You must specify a name"
        if not groupID:
            return "You must specify a group"
        if not collectionID:
            collectionID = CreateCollection(name, groupID, description, defaultView, dynamicCounterID, dynamicSubjectID, dynamicAggregateFunction, dynamicCount)
            redirect("Counters?collectionID=%s" % collectionID)

        sql = "UPDATE metric.collections SET collectionName = '%s', description = '%s', groupID = %d, dynamicCounterID = %s, dynamicSubjectID = %s, dynamicAggregateFunction = %s, dynamicCount = %s WHERE collectionID = %d" % (name, description, groupID, SqlIntOrNULL(dynamicCounterID), SqlIntOrNULL(dynamicSubjectID, True), SqlStringOrNULL(dynamicAggregateFunction), SqlIntOrNULL(dynamicCount), collectionID)
        dbmetrics.executesql(sql)

        UpdateConfig("metric.collections", "collectionID=%s" % collectionID, config)

        lst = request.vars.collectionCounters.split(",")
        for i, l in enumerate(lst):
            if not l:
                continue
            label = MakeSafe(getattr(request.vars, "label_%s" % l))
            severityThreshold = getattr(request.vars, "severityThreshold_%s" % l)
            aggregateFunction = getattr(request.vars, "aggregateFunction_%s" % l)
            goal = getattr(request.vars, "goal_%s" % l)
            goalType = getattr(request.vars, "goalType_%s" % l)
            goalDirection = getattr(request.vars, "goalDirection_%s" % l)
            sql = "UPDATE metric.collectionCounters SET collectionIndex = %d, aggregateFunction = '%s', label = '%s', severityThreshold = %f, goal=%f, goalType='%s', goalDirection='%s' WHERE collectionCounterID = %d" % (i+1, aggregateFunction, label, float(severityThreshold or 0), float(goal or 0), goalType, goalDirection, int(l))
            dbmetrics.executesql(sql)
            LogQuery(sql)

        cache.ram("collections", None, 0)

        if request.vars.referer and "Login" not in request.vars.referer and request.vars.referer != "None" and "collectionID" in request.vars.referer:
            redirect(request.vars.referer)
        else:
            redirect("Collections?collectionID=%s" % collectionID)

    name = ""
    description = ""
    collectionID = int(request.vars.collectionID or 0)
    collection = None
    groupID = None
    collectionCounters = None
    defaultView = "graphs"
    collectionType = "static"
    dynamicCounterID = None
    dynamicSubjectID = None
    dynamicAggregateFunction = None
    dynamicCount = None
    config = {}
    if collectionID:
        collectionID = int(collectionID)
        collection = GetCollection(collectionID)
        config = collection.config
        name = collection.collectionName
        description = collection.description
        groupID = collection.groupID
        defaultView = collection.config.get("defaultView", "graphs")
        if collection.dynamicCounterID:
            collectionType = "dynamic"
            dynamicCounterID = collection.dynamicCounterID
            dynamicSubjectID = collection.dynamicSubjectID
            dynamicAggregateFunction = collection.dynamicAggregateFunction
            dynamicCount = collection.dynamicCount

        sql = """
            SELECT *
              FROM metric.collectionCountersEx cc WHERE collectionID = %d
              ORDER BY cc.collectionID, [collectionIndex] ASC
        """ % collectionID
        LogQuery(sql)
        collectionCounters = dbmetrics.executesql(sql)
    
    return {
        "collection"    : collection,
        "collectionID"  : collectionID,
        "name"          : name,
        "description"   : description,
        "groupID"       : groupID,
        "groups"        : GetGroups(),
        "collectionCounters" : collectionCounters,
        "defaultView"   : defaultView,
        "collectionType": collectionType,

        "dynamicCounterID" : dynamicCounterID,
        "dynamicSubjectID" : dynamicSubjectID,
        "dynamicAggregateFunction" : dynamicAggregateFunction,
        "dynamicCount"     : dynamicCount,
        "config"        : config,
        }


@FuncTime
def DeleteCounter():
    LoggedIn()
    counterID = int(request.vars.counterID)
    sql = "EXEC metric.Counters_Delete %d" % counterID
    rows = dbmetrics.executesql(sql)
    cache.ram("counterinfo", None, 0)
    redirect("Reports")


def SqlStringOrNULL(v):
    if v:
        return "'%s'" % v
    else:
        return "NULL"


def SqlIntOrNULL(v, allowZero=False):
    if v is None or v == "":
        return "NULL"
    if allowZero:
        return "%s" % v
    else:
        if v and int(v) > 0:
            return "%s" % v
        else:
            return "NULL"

def SqlFloatOrNULL(v, allowZero=False):
    if v is None or v == "":
        return "NULL"
    if allowZero:
        return "%f" % v
    else:
        if v and float(v) > 0:
            return "%s" % v
        else:
            return "NULL"

@FuncTime
def DeleteCounterData():
    counterID = int(request.vars.counterID)
    if not counterID:
        return "No counter specified"
    if request.vars.deleteall:
        sql = "EXEC metric.Counters_DeleteData %s, '2000-01-01', '2020-01-01'" % (counterID)
        dbmetrics.executesql(sql)
        redirect(URL("EditCounter?counterID=%s&message=All data deleted from counter" % counterID))
    elif "deleteday" in request.vars:
        d = request.vars.deleteday.split(" ")[1]
        sql = "EXEC metric.Counters_DeleteData %s, '%s'" % (counterID, d)
        dbmetrics.executesql(sql)
        redirect(URL("EditCounter?counterID=%s&message=Data from %s deleted from counter" % (counterID, d)))

    counter = GetCounterInfo(counterID)
    response.title = "Delete counter data"
    txt = "<h4>Last Chance! Do you want to delete all rows from <i>%s (%s)</i>?</h4>" % (counter.counterName, counter.counterID)
    txt += "<form method=post action=DeleteCounterData><input type=hidden name=counterID value=%s><input name=deleteall type=submit value=\"DELETE ALL DATA\" style=\"color:crimson;font-weight:bold;\" OnClick=\"return confirm('Last chance, really clear this counter?');\">" % counterID
    sql = """
    SELECT counterDate, COUNT(*) FROM zmetric.dateCounters 
     WHERE counterID = %s
    GROUP BY counterDate
    ORDER BY counterDate DESC
    """ % counterID
    rows = dbmetrics.executesql(sql)
    txt += "<br><h5>Here is the data you are about to remove</h5><table><tr><th>Date</th><th>Rows</th></tr>"
    for r in rows:
        txt += "<tr><td>%s</td><td>%s</td><td><input name=\"deleteday\" type=submit value=\"Delete %s\" style=\"color:crimson;font-weight:bold;\" title=\"Delete this day\" OnClick=\"return confirm('Are you sure you want to delete the data in this counter for this day?');\"></td></tr>" % (r[0], FmtAmt(r[1]), r[0])
    txt += "</table><br><br></form>"
    return {"txt": XML(txt)}


@FuncTime
def EditCounter():
    LoggedIn(True)
    if request.post_vars:
        v = request.post_vars
        name = MakeSafe(v.name)
        description = MakeSafe(v.description)
        source = MakeSafe(v.source)
        sourceType = MakeSafe(v.sourceType)
        procedureName = MakeSafe(v.procedureName)
        procedureOrder = v.procedureOrder
        if procedureOrder == "":
            procedureOrder = 255
        procedureOrder = int(procedureOrder)
        subjectID = MakeSafe(v.subjectID)
        keyID = MakeSafe(v.keyID)
        groupID = int(v.groupID)
        counterID = int(v.counterID)
        parentCounterID = int(v.parentCounterID)
        subjectLookupTableID = int(v.subjectLookupTableID)
        keyLookupTableID = int(v.keyLookupTableID)
        counterIdentifier = v.counterIdentifier
        published = 1 if v.published else 0
        absoluteValue = 1 if v.absoluteValue else 0
        obsolete = 1 if v.obsolete else 0
        if keyLookupTableID and not keyID:
            #return "You must put in a keyID if you specify a Key lookup table"
            keyID = "unknownID"
        if subjectLookupTableID > 0 and not subjectID:
            return "You must put in a subjectID if you specify a Subject lookup table"
        if not keyLookupTableID and keyID:
            return "keyID doesn't make any sense unless you specify a Key lookup table"
        if not subjectLookupTableID and subjectID:
            return "subjectID doesn't make any sense unless you specify a Subject lookup table"
        if subjectLookupTableID > 0 and keyLookupTableID == 0:
            return "You cannot specify a subject without a key. You should move your subject to the key instead"
        if subjectLookupTableID > 0 and sourceType == "MANUAL":
            return "You cannot have a subjectID on a Manual counter"
        if procedureOrder > 255 or procedureOrder < 0:
            return "Procedure Order must be between 0 and 200"
        if not name:
            return "You must specify a name"
        if not counterIdentifier:
            return "You must specify an identifier"
        sql = "SELECT * FROM zmetric.counters WHERE LOWER(counterIdentifier) = '%s' AND counterID <> %s" % (counterIdentifier.lower(), counterID)
        rs = dbmetrics.executesql(sql)
        if len(rs) > 0:
            return "Your identifier string is already in use"

        if counterID > 0:
            sql = """
                UPDATE zmetric.counters 
                   SET counterName = '%s', counterIdentifier = '%s', description = '%s', groupID = %d, parentCounterID = %d,
                       subjectLookupTableID = %s, keyLookupTableID = %s, source = '%s', procedureName = '%s', procedureOrder = '%s', keyID = %s, subjectID = %s, published = %s, sourceType = '%s', absoluteValue = %s, obsolete = %s
                 WHERE counterID = %d""" % (name, counterIdentifier, description, groupID, parentCounterID, SqlIntOrNULL(subjectLookupTableID), SqlIntOrNULL(keyLookupTableID), source, procedureName, procedureOrder, SqlStringOrNULL(keyID), SqlStringOrNULL(subjectID), published, sourceType, absoluteValue, obsolete, counterID)
            dbmetrics.executesql(sql)
            sql = "UPDATE zmetric.counters SET modifyDate = GETUTCDATE() WHERE counterID = %d" % (counterID)
            dbmetrics.executesql(sql)
            sql = "UPDATE zmetric.counters SET groupID = %d WHERE parentCounterID = %d" % (groupID, counterID)
            dbmetrics.executesql(sql)
        else:
            sql = """EXEC zmetric.Counters_Insert 'D', NULL, '%s', %s, '%s', %s, %s, '%s', %s, %s, %s, NULL, 0, '%s', %s, %s, NULL, '%s', %s, '%s', NULL, NULL, '%s'"""  % (name, groupID, description, SqlIntOrNULL(subjectLookupTableID), SqlIntOrNULL(keyLookupTableID), source, SqlStringOrNULL(subjectID), SqlStringOrNULL(keyID), absoluteValue, procedureName, procedureOrder, parentCounterID, counterIdentifier, published, sourceType, session.userName)
            counterID = dbmetrics.executesql(sql)[0][0]

            if session.teamName:
                DoAddTag(TAG_REPORT, counterID, session.teamName)


        sql = "DELETE FROM zmetric.columns WHERE counterID = %d" % counterID
        dbmetrics.executesql(sql)
        if subjectLookupTableID < 0:
            colIds = ""
            for i in xrange(20):
                counterColumnID = getattr(v, "counterColumnID_%d" % i)
                counterColumnName = getattr(v, "counterColumnName_%d" % i)
                if counterColumnName:
                    counterColumnName = counterColumnName.replace("'", "\'")
                counterColumnDescription = getattr(v, "counterColumnDescription_%d" % i)
                if counterColumnDescription:
                    counterColumnDescription = "'%s'" % counterColumnDescription.replace("'", "\'")
                else:
                    counterColumnDescription = "NULL"
                counterColumnOrder = getattr(v, "counterColumnOrder_%d" % i)
                if not counterColumnOrder:
                    counterColumnOrder = "0"
                if counterColumnID:
                    colIds += "%s, " % counterColumnID
                    sql = "DELETE FROM zmetric.columns WHERE counterID = %s and columnID = %s" % (counterID, counterColumnID)
                    dbmetrics.executesql(sql)
                    sql = "INSERT INTO zmetric.columns (counterID, columnID, columnName, description, [order]) VALUES (%s, %s, '%s', %s, %s)" % (counterID, counterColumnID, counterColumnName, counterColumnDescription, counterColumnOrder)
                    dbmetrics.executesql(sql)
            if colIds: colIds = colIds[:-2]
        else:
            colIds = "0"
        sql = "DELETE FROM zmetric.columns WHERE counterID = %s and columnID NOT IN (%s)" % (counterID, colIds)
        dbmetrics.executesql(sql)

        if keyLookupTableID == -1:
            name = "%s - Lookup Table" % counterIdentifier
            description = "This lookup table was created specifically for the counter %s" % counterIdentifier
            source = ""
            lookupID = ""
            lookupTableIdentifier = counterIdentifier + "_lookupTable"
            sql = """EXEC zsystem.LookupTables_Insert NULL, '%s', '%s', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '%s', 'MAX'""" % (name, description, lookupTableIdentifier)
            try:
                dbmetrics.executesql(sql)
            except:
                raise
            
            sql = "SELECT lookupTableID FROM zsystem.lookupTables WHERE lookupTableIdentifier = '%s'" % lookupTableIdentifier
            lookupTableID = dbmetrics.executesql(sql)[0].lookupTableID
            sql = "UPDATE zmetric.counters SET keyLookupTableID = %d WHERE counterID = %d" % (lookupTableID, counterID)
            dbmetrics.executesql(sql)

        cache.ram("counter_%s" % counterID, None, 0)
        cache.ram("countercolumns", None, 0)
        cache.ram("counterinfo", None, 0)
        redirect(URL("Report?counterID=%d" % counterID))

    counterName = ""
    description = ""
    counterID = int(request.vars.counterID or 0)
    fromCounterID = int(request.vars.fromCounterID or 0)
    counter = None
    groupID = None
    source = ""
    procedureName = ""
    procedureOrder = 200
    parentCounterID = 0
    subjectLookupTableID = 0
    keyLookupTableID = 0
    cols = None
    keyID = ""
    subjectID = ""
    counterIdentifier = ""
    hidden = 0
    published = 1
    sourceType = "DB"
    absoluteValue = 0
    obsolete = 0

    if counterID or fromCounterID:
        counterID = int(counterID)
        counter = GetCounterInfo(counterID or fromCounterID)
        counterName = counter.counterName
        if fromCounterID: counterName += " (copy)"
        description = counter.description
        groupID = counter.groupID
        parentCounterID = counter.parentCounterID
        source = counter.source
        sourceType = counter.sourceType
        procedureName = counter.procedureName
        procedureOrder = counter.procedureOrder
        subjectLookupTableID = counter.subjectLookupTableID
        keyLookupTableID = counter.keyLookupTableID
        keyID = counter.keyID
        subjectID = counter.subjectID
        counterIdentifier = counter.counterIdentifier
        hidden = counter.hidden
        published = counter.published
        absoluteValue = counter.absoluteValue
        obsolete = counter.obsolete
        cols = GetCounterColumnsForCounter(counterID or fromCounterID)
        if cols:
            subjectLookupTableID = -1
    counterData = ""
    if counterID:
        try:
            sql = "EXEC metric.Counters_Stats %s" % counterID
            row = dbmetrics.executesql(sql)[0]
            firstDate = row.firstDate
            lastDate = row.lastDate
            numRows = row.count10000

            counterData = collections.OrderedDict()
            counterData["First Date"] = firstDate
            counterData["Last Date"] = lastDate
            counterData["Number of Rows"] = FmtAmt(numRows)
            if numRows >= 10000:
                counterData["Number of Rows"] = "More than %s" % FmtAmt(numRows)
        except IndexError:
            pass
        #, "lastDate": lastDate, "numRows": numRows}

    return {
        "counter"         : counter,
        "counterID"       : counterID,
        "name"            : counterName,
        "description"     : description,
        "groupID"         : groupID,
        "groups"          : GetGroups(),
        "counters"        : GetCounters(),
        "parentCounterID" : parentCounterID,
        "sourceType"      : sourceType,
        "source"          : source,
        "procedureName"   : procedureName,
        "procedureOrder"  : procedureOrder,
        "lookupTables"    : GetLookupTables(),
        "subjectLookupTableID" : subjectLookupTableID,
        "keyLookupTableID" : keyLookupTableID,
        "columns" : cols or {},
        "keyID"           : keyID,
        "subjectID"       : subjectID,
        "counterIdentifier": counterIdentifier,
        "counterData"     : counterData,
        "hidden"          : hidden,
        "published"       : published,
        "sourceTypes"     : GetSourceTypes(),
        "absoluteValue"   : absoluteValue,
        "obsolete"        : obsolete,
    }


def GetSourceTypes():
    sql = "select * from metric.sourceTypes ORDER BY sourceTypeText"
    rows = dbmetrics.executesql(sql)
    return rows

@FuncTime
def ViewLookupTables():
    return {"tables" : GetLookupTables()}


@FuncTime
def ViewLookupTable():
    lookupTableID = int(request.vars.lookupTableID)
    t = GetLookupTables().get(lookupTableID)

    txt = "<h2>View Lookup Table</h2>"
    txt += "<a href=\"ViewLookupTables\" class=normaltext>Go back</a><br><table>"
    txt += "<tr><td>lookupTableID</td><td>%s</td></tr>" % (t.lookupTableID)
    txt += "<tr><td>lookupTableName</td><td>%s</td></tr>" % (t.lookupTableName)
    txt += "<tr><td>lookupTableIdentifier</td><td>%s</td></tr>" % (t.lookupTableIdentifier)
    txt += "<tr><td>description</td><td>%s</td></tr>" % (t.description)
    txt += "<tr><td>source</td><td>%s</td></tr>" % (t.source)
    txt += "<tr><td>sourceForID</td><td>%s</td></tr>" % (t.sourceForID)
    txt += "<tr><td>lookupID</td><td>%s</td></tr>" % (t.lookupID)
    txt += "<tr><td>parentID</td><td>%s</td></tr>" % (t.parentID or "")
    txt += "<tr><td>parentLookupTableID</td><td>%s</td></tr>" % (t.parentLookupTableID or "")
    txt += "<tr><td>link</td><td><pre>%s</pre></td></tr>" % ((t.link or "").replace("<", "&lt;") or "")
    txt += "<tr><td>label</td><td><pre>%s</pre></td></tr>" % (t.label or "")
    txt += "</table>"

    txt += "<br><a href=\"EditLookupTable?lookupTableID=%s\">Edit lookup table</a><br><br>" % t.lookupTableID

    sql = "SELECT * FROM zmetric.counters WHERE subjectLookupTableID = %d or keyLookupTableID = %d ORDER BY counterName ASC" % (lookupTableID, lookupTableID)
    rows = dbmetrics.executesql(sql)
    txt += "<h4>Reports using this lookup table</h4><table class=datatable><tr><th>Report</th></tr>"
    for r in rows:
        txt += "<tr><td><a href=\"Report?counterID=%s\">%s</a></td></tr>" % (r.counterID, r.counterName)
    txt += "</table><br>"

    sql = "SELECT TOP 100 lookupID, lookupText = IsNull(fullText, lookupText) FROM zsystem.lookupValues WHERE lookupTableID = %d" % lookupTableID
    rows = dbmetrics.executesql(sql)
    txt += "<h4>Top 100 rows from zsystem.lookupValues for this lookup table</h4><table class=datatable><tr><th>lookupID</th><th>lookupText</th></tr>"
    for r in rows:
        txt += "<tr><td width=\"1%%\">%s</td><td>%s</td></tr>" % (r.lookupID, r.lookupText)
    txt += "</table><br>"
    return {"txt": XML(txt)}


@FuncTime
def DeleteLookupTable():
    LoggedIn(True)
    lookupTableID = int(request.vars.lookupTableID)
    sql = "EXEC metric.LookupTables_Delete %d" % lookupTableID
    rows = dbmetrics.executesql(sql)
    redirect("/ViewLookupTables")


@FuncTime
def ViewMissingCounterDays():
    sql = "EXEC GetMissingCounterDays"
    rows = dbmetrics.executesql(sql)
    missingDatesByCounter = collections.defaultdict(list)
    counters = GetCounters()
    for r in rows:
        missingDatesByCounter[("%s | %s" % (counters[r.counterID].groupName, counters[r.counterID].counterName), r.counterID)].append(datetime.datetime.strptime(r.counterDate, "%Y-%m-%d"))
    return {
        "missingDatesByCounter"  : missingDatesByCounter,
        "counters"               : counters,
    }

@FuncTime
def ViewReadyCounters():
    sql = "EXEC GetMissingCounterDays"
    rows = dbmetrics.executesql(sql)
    missingDatesByCounter = collections.defaultdict(list)
    counters = GetCounters()
    for r in rows:
        missingDatesByCounter[("%s | %s" % (counters[r.counterID].groupName, counters[r.counterID].counterName), r.counterID)].append(datetime.datetime.strptime(r.counterDate, "%Y-%m-%d"))
    return {
        "missingDatesByCounter"  : missingDatesByCounter,
        "counters"               : counters,
    }

@FuncTime
def EditLookupTable():
    LoggedIn(True)
    if request.post_vars:
        v = request.post_vars
        name = MakeSafe(v.name)
        lookupTableID = int(v.lookupTableID or 0)
        lookupTableIdentifier = MakeSafe(v.lookupTableIdentifier)
        if not lookupTableIdentifier:
            return "Table Identifier cannot be empty"

        description = MakeSafe(v.description)
        source = MakeSafe(v.source)
        lookupID = MakeSafe(v.lookupID)
        parentID = v.parentID
        link = MakeSafe(v.link)
        label = MakeSafe(v.label)
        sourceForID = MakeSafe(v.sourceForID)
        if sourceForID:
            sourceForID = "'%s'" % sourceForID
        else:
            sourceForID = "NULL"
        parentLookupTableID = int(v.parentLookupTableID or 0)
        if not parentID:
            parentID = "NULL"
        if parentLookupTableID <= 0:
            parentLookupTableID = "NULL"

        if not name:
            return "You must specify a name"
        if lookupTableID > 0:
            sql = """
                UPDATE zsystem.lookupTables
                   SET lookupTableName = '%s', description = '%s', source = '%s', lookupID = '%s', parentID = '%s', link = '%s',
                       parentLookupTableID = %s, lookupTableIdentifier = '%s', sourceForID = %s, label = %s
                 WHERE lookupTableID = %d""" % (name, description, source, lookupID, parentID, link, parentLookupTableID, lookupTableIdentifier, sourceForID, SqlStringOrNULL(label), lookupTableID)
            try:
                dbmetrics.executesql(sql)
            except Exception, e:
                return e
        else:
            sql = """EXEC zsystem.LookupTables_Insert NULL, '%s', '%s', NULL, NULL, '%s', '%s', %s, %s, '%s', '%s', %s, %s""" % (name, description, source, lookupID, parentID, parentLookupTableID, link, lookupTableIdentifier, sourceForID, SqlStringOrNULL(label))
            rows = dbmetrics.executesql(sql)
            lookupTableID = rows[0][0]

        cache.ram.clear()
        redirect("ViewLookupTable?lookupTableID=%d" % lookupTableID)

    name = ""
    description = ""
    lookupTableID = int(request.vars.lookupTableID or 0)
    source = lookupID = ""
    parentLookupTableID = 0
    parentID = 0
    link = ""
    lookupTableIdentifier = ""
    sourceForID = ""
    label = ""

    if lookupTableID:
        lookupTableID = int(lookupTableID)
        sql = "SELECT * FROM zsystem.lookupTablesEx WHERE lookupTableID = %d" % lookupTableID
        LogQuery(sql)
        tblRow = dbmetrics.executesql(sql)[0]
        name = tblRow.lookupTableName
        description = tblRow.description
        source = tblRow.source
        lookupTableIdentifier = tblRow.lookupTableIdentifier

        lookupID = tblRow.lookupID
        parentID = tblRow.parentID
        link = tblRow.link
        label = tblRow.label
        parentLookupTableID = tblRow.parentLookupTableID
        sourceForID = tblRow.sourceForID
    
    return {
        "lookupTableID"   : lookupTableID,
        "name"            : name,
        "description"     : description,
        "lookupID"        : lookupID,
        "parentID"        : parentID,
        "parentLookupTableID" : parentLookupTableID,
        "source"          : source,
        "lookupTables"    : GetLookupTables(),
        "link"            : link,
        "label"           : label,
        "lookupTableIdentifier" : lookupTableIdentifier,
        "sourceForID"     : sourceForID,

        }


def GetLookupTables():
    sql = """SELECT lookupTableID, lookupTableName, source, lookupID, parentID, parentLookupTableID, description, link, lookupTableIdentifier, sourceForID, label
  FROM zsystem.lookupTables
 WHERE lookupTableID < 2000000000
 ORDER BY lookupTableName"""
    rows = dbmetrics.executesql(sql)
    return GetDictFromRowset(rows)


def GetLookupTable(lookupTableID):
    sql = """SELECT * FROM zsystem.lookupTables WHERE lookupTableID = %d""" % lookupTableID
    return dbmetrics.executesql(sql)[0]


def GetCounterColumnsForAllCounters():
    sql = """
        SELECT counterID, columnID AS subjectID, columnName, description, [order]
          FROM zmetric.columns
         ORDER BY counterID ASC
    """
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    ret = {}
    for r in rows:
        if r.counterID not in ret:
            ret[r.counterID] = {}
        ret[r.counterID][r.subjectID] = r
    return ret


def GetCounterColumnsForCounter(counterID):
    d = cache.ram("countercolumns", lambda:GetCounterColumnsForAllCounters(), CACHE_TIME)
    return d.get(counterID, {})


def GetTables():
    sql = """
SELECT lookupTableID, lookupTableName, source, lookupID, parentID, parentLookupTableID
  FROM zsystem.lookupTables
 ORDER BY lookupTableName
    """
    rows = dbmetrics.executesql(sql)
    return GetDictFromRowset(rows)


@FuncTime
def ManageCollectionCounters():
    LoggedIn()

    collectionID = int(request.vars.collectionID)
    lst = []
    collection = GetCollection(collectionID)
    counters = collection.counters

    return {"collection": collection}


@FuncTime
def ManageGroups():
    LoggedIn(True)
    sql = """SELECT g.groupID, g.groupName, g.[order], numCounters=COUNT(DISTINCT c.counterID), numCollections=COUNT(DISTINCT cc.collectionID)
               FROM zmetric.groups g 
                 LEFT JOIN zmetric.counters c ON c.groupID = g.groupID
                 LEFT JOIN metric.collections cc ON cc.groupID = c.groupID
              WHERE g.groupID < 30000
              GROUP BY g.groupID, g.groupName, g.[order]
              ORDER BY g.[order], groupName"""
    rows = dbmetrics.executesql(sql)
    return {"groups": rows}


@FuncTime
def ManageCounters():
    LoggedIn(True)
    sql = """SELECT theID=c.counterID, name=c.counterName, c.description, c.groupID, c.groupName, parentID=c.parentCounterID, c.modifyDate, c.createDate, c.userName, c.groupOrder, c.[order], c.counterIdentifier, NUM=COUNT(c2.counterID)
               FROM zmetric.countersEx c
                LEFT JOIN zmetric.counters c2 ON c2.parentCounterID = c.counterID
              WHERE ISNULL(c.parentCounterID, 0) = 0 AND c.counterID < 30000
             GROUP BY c.counterID, c.counterName, c.description, c.groupID, c.groupName, c.parentCounterID, c.modifyDate, c.createDate, c.userName, c.groupOrder, c.[order], c.counterIdentifier
             ORDER BY c.groupOrder, c.groupName, c.[order], c.counterIdentifier, c.counterName ASC"""
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    return {
        "counters"   : rows,
        "context"    : "Counters",
    }


@FuncTime
def ManageCollections():
    LoggedIn(True)
    sql = """
SELECT theID=c.collectionID, name=c.collectionName, c.description, c.groupID, c.groupName, parentID=0, c.[order], NUM=0
  FROM metric.collectionsEx c
 ORDER BY c.groupOrder, c.groupName, c.[order], c.collectionName ASC
    """
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    return {
        "collections": rows,
        "context"    : "Collections",
    }


@FuncTime
def EditGroup():
    LoggedIn(True)
    if request.post_vars:
        v = request.post_vars
        name = MakeSafe(v.name)
        description = MakeSafe(v.description)
        groupID = int(v.groupID or 0)
        if not name:
            return "You must specify a name"
        if groupID:
            sql = "UPDATE zmetric.groups SET groupName = '%s', description = '%s' WHERE groupID = %d" % (name, description, groupID)
        else:
            sql = "INSERT INTO zmetric.groups (groupName, description, [order], groupID) VALUES ('%s', '%s', 0, %s)" % (name, description, GetTopGroupID()+1)
        dbmetrics.executesql(sql)
        cache.ram.clear()
        redirect("/ManageGroups")

    name = ""
    description = ""
    groupID = int(request.vars.groupID or 0)
    group = None
    if groupID:
        groupID = int(groupID)
        sql = """SELECT groupName, description FROM zmetric.groups WHERE groupID = %d""" % groupID
        group = dbmetrics.executesql(sql)
        name = group[0].groupName
        description = group[0].description
    
    return {
        "group"         : group,
        "name"          : name,
        "description"   : description,
        "groupID"       : groupID,
        }


@FuncTime
def RemoveGroup():
    LoggedIn(True)
    groupID = int(request.vars.groupID)
    sql = "EXEC metric.Groups_Delete %d" % groupID
    rows = dbmetrics.executesql(sql)
    redirect("/ManageGroups")

@FuncTime
def ManageSettings():
    sql = "SELECT [group], [key], [value], [allowUpdate], [description] FROM zsystem.settings ORDER BY [group], [key]"
    settings = dbmetrics.executesql(sql)
    return {"settings": settings}

@FuncTime
def EditSetting():
    if request.vars.send:
        group = MakeSafe(request.vars.group)
        key = MakeSafe(request.vars.key)
        val = MakeSafe(request.vars.value)
        sql = "UPDATE zsystem.settings SET [value] = '%s' WHERE [group] = '%s' AND [key] = '%s' AND allowUpdate = 1" % (val, group, key)
        dbmetrics.executesql(sql)
        redirect("ManageSettings?message=Settings Have been updated")
    else:
        group = MakeSafe(request.vars.group)
        key = MakeSafe(request.vars.key)
        sql = "SELECT [group], [key], [value], [allowUpdate], [description] FROM zsystem.settings WHERE [group] = '%s' AND [key] = '%s' AND allowUpdate = 1 ORDER BY [group], [key]" % (group, key)
        try:
            row = dbmetrics.executesql(sql)[0]
        except:
            return "Setting not found"
        return {
            "group": group,
            "key": key,
            "value" : row.value,
            }

@FuncTime
def Admin():
    LoggedIn()
    if request.post_vars:
        v = request.post_vars
        if v.adminPassword == ADMIN_PASSWORD:
            session.admin = 1
            redirect(request.vars.redirect or URL("/Admin"))
        else:
            error = "Incorrect password"
    if session.admin:
        pass
    return {
        "error"    : "",
        "redirect" : request.vars.redirect,
        "functions" : [
                    [URL("ManageCounters"), "Manage Counters"], 
                    [URL("ManageCollections"), "Manage Collections"], 
                    [URL("ManageGroups"), "Manage Groups"], 
                    [URL("ViewLookupTables"), "Manage Lookup Tables"],
                    [],
                    [URL("EditCounter?counterID=0"), "Add new Counter"], 
                    [URL("EditLookupTable?lookupTableID=0"), "Add new Lookup Table"],
                    [URL("EditGroup?groupID=0"), "Add new Group"],

                    [],
                    [URL("ManageMarkerCategories"), "Manage Marker Categories"], 
                    [],
                    [URL("ViewMissingCounterDays"), "View all Missing Counter days"], 
                    [],
                    [URL("SafeSQL"), "Execute SQL"], 
                    [URL("ViewPageLookups"), "View page lookups"],
                    [URL("TaskLogs"), "View Task Logs"],
                    [URL("ManageSettings"), "Manage Settings"], 
                    [URL("ClearCache"), "Clear Cache"], 
                    ],
        }


@FuncTime
def ViewPageLookups():
    filt = request.vars.filter
    mr = ""
    if filt:
        filt = filt.lower()
        mr = "WHERE LOWER(method) LIKE '%%%(filter)s%%' OR LOWER(url) LIKE '%%%(filter)s%%' OR LOWER(userName) LIKE '%%%(filter)s%%' OR LOWER(hostName) LIKE '%%%(filter)s%%'" % {"filter": filt}
    sql = "SELECT TOP 1000 * FROM pageViews %s ORDER BY viewID DESC" % mr
    rows = dbmetrics.executesql(sql)
    return {"rows" : rows}


def OrderGroupsDragDrop():
    lst = request.vars.order.split(",")
    for i, l in enumerate(lst):
        if l:
            sql = "UPDATE zmetric.groups SET [order] = %d WHERE groupID = %d" % (i+1, int(l))
            dbmetrics.executesql(sql)
            LogQuery(sql)
    cache.ram.clear()


def OrderCollectionsFromForm():
    lst = request.vars.order.split(",")
    for i, l in enumerate(lst):
        if l:
            sql = "UPDATE metric.collectionCounters SET collectionIndex = %d WHERE collectionCounterID = %d" % (i+1, int(l))
            dbmetrics.executesql(sql)
            LogQuery(sql)
    #cache.ram("collections", None, 0) 

def OrderDigestSectionsDragDrop():
    lst = request.vars.order.split(",")
    which = request.vars.which
    if which == "sections":
        whichTable = "digestSections"
        whichCol = "sectionID"
    else:
        whichTable = "digestAlerts"
        whichCol = "alertID"
    digestID = int(request.vars.digestID)
    for i, l in enumerate(lst):
        if l:
            sql = "UPDATE metric.%s SET [position] = %d WHERE digestID = %d AND %s = %s" % (whichTable, i+1, digestID, whichCol, int(l))
            dbmetrics.executesql(sql)


def OrderCountersDragDrop():
    lst = request.vars.order.split(",")
    i = 0
    lastGroupID = 0
    sql = "SELECT counterID, [order], groupID FROM zmetric.counters"
    rows = dbmetrics.executesql(sql)
    allCounters = GetDictFromRowset(rows)
    for l in lst:
        if not l:
            continue
        ll = l.split(":")
        try:
            groupID = int(ll[0])
        except:
            groupID = 0
        counterID = int(ll[1])
        if groupID != lastGroupID:
            i = 0
            lastGroupID = groupID
        oldCounter = allCounters[counterID]
        order = i+1
        if oldCounter.order != order or oldCounter.groupID != groupID:
            sql = "UPDATE zmetric.counters SET [order] = %d, groupID = %s WHERE counterID = %d" % (order, groupID, counterID)
            dbmetrics.executesql(sql)
            sql = "UPDATE zmetric.counters SET [order] = %d, groupID = %s WHERE parentCounterID = %d" % (i+1, groupID, counterID)
            dbmetrics.executesql(sql)
        i += 1

    cache.ram.clear()
    return "$('#working').hide();"


def OrderCollectionsDragDrop():
    lst = request.vars.order.split(",")
    i = 0
    lastGroupID = 0
    sql = "SELECT collectionID, [order], groupID FROM metric.collections"
    rows = dbmetrics.executesql(sql)
    allCollections = GetDictFromRowset(rows)
    for l in lst:
        if not l:
            continue
        ll = l.split(":")
        groupID = int(ll[0])
        collectionID = int(ll[1])
        if groupID != lastGroupID:
            i = 0
            lastGroupID = groupID
        oldCollection = allCollections[collectionID]
        order = i+1
        if oldCollection.order != order or oldCollection.groupID != groupID:
            sql = "UPDATE metric.collections SET [order] = %d, groupID = %s WHERE collectionID = %d" % (order, groupID, collectionID)
            dbmetrics.executesql(sql)
        i += 1

    cache.ram.clear()
    return "$('#working').hide();"


def GetTopCollectionID():
    sql = "SELECT TOP 1 collectionID FROM metric.collections ORDER BY collectionID DESC"
    rows = dbmetrics.executesql(sql)
    LogQuery(sql)
    if rows:
        return rows[0].collectionID
    return 0


def GetTopGroupID():
    sql = "SELECT TOP 1 groupID FROM zmetric.groups ORDER BY groupID DESC"
    rows = dbmetrics.executesql(sql)
    LogQuery(sql)
    if rows:
        return rows[0].groupID
    return 0


def GetTopLookupTableID():
    sql = "SELECT TOP 1 lookupTableID FROM zsystem.lookupTables ORDER BY lookupTableID DESC"
    rows = dbmetrics.executesql(sql)
    LogQuery(sql)
    if rows:
        return rows[0].lookupTableID
    return 0


def GetTopCounterID():
    sql = "SELECT TOP 1 counterID FROM zmetric.counters ORDER BY counterID DESC"
    rows = dbmetrics.executesql(sql)
    LogQuery(sql)
    if rows:
        return rows[0].counterID
    return 0


def GetTopCollectionCounterIndex(collectionID):
    sql = "SELECT TOP 1 collectionIndex FROM metric.collectionCounters WHERE collectionID = %s ORDER BY collectionIndex DESC" % collectionID
    rows = dbmetrics.executesql(sql)
    LogQuery(sql)
    if rows:
        return rows[0].collectionIndex
    return 0


def CreateCollection(name=None, groupID=0, description="", defaultView="graphs", dynamicCounterID=None, dynamicSubjectID=None, dynamicAggregateFunction=None, dynamicCount=None):
    collectionName = name or "New Collection"
    sql = """
        INSERT INTO metric.collections (collectionName, groupID, description, dynamicCounterID, dynamicSubjectID, dynamicAggregateFunction, dynamicCount, userName)
        VALUES ('%s', %s, '%s', %s, %s, %s, %s, '%s')
    """ % (collectionName, groupID, description, SqlIntOrNULL(dynamicCounterID), SqlIntOrNULL(dynamicSubjectID, True), SqlStringOrNULL(dynamicAggregateFunction), SqlIntOrNULL(dynamicCount), session.userName)
    dbmetrics.executesql(sql)
    LogQuery(sql)
    collectionID = GetTopCollectionID()

    UpdateConfig("metric.collections", "collectionID=%s" % collectionID, {"defaultView": defaultView})

    if session.teamName:
        DoAddTag(TAG_COLLECTION, collectionID, session.teamName)

    return collectionID


def GetGroups():
    sql = """
        SELECT groupID, groupName
          FROM zmetric.groups
        ORDER BY groupName ASC
    """
    rows = dbmetrics.executesql(sql)
    return rows

def LogQuery(sql):
    if sql not in cache.ram.storage:
        response.query.append(sql)


def GetAllCountersInfo():
    # counterID, counterName, subjectLookupTableID, keyLookupTableID, groupID, groupName, description, subjectID, keyID, absoluteValue, procedureName, sourceType, source, [order], procedureOrder, parentCounterID, userName, createDate, modifyDate, counterIdentifier, hidden, published, obsolete
    sql = """
        SELECT *
          FROM zmetric.countersEx
        """
    LogQuery(sql)
    return dbmetrics.executesql(sql)

def GetCounterInfo(counterID):
    counterInfos = cache.ram("counterinfo", lambda:GetAllCountersInfo(), CACHE_TIME_FOREVER)
    for c in counterInfos:
        if c.counterID == counterID:
            return c
    return None


def DiffReport():
    subjectID = request.vars.subjectID
    counterID = request.vars.counterID
    excludeCount = int(request.vars.excludeCount or 100)
    numRows = int(request.vars.numRows or 20)
    numDays = int(request.vars.numDays or 7)
    order = int(request.vars.order or 0)
    sort = request.vars.sort or "P"
    rows = []
    counterInfo = None
    counterSubjects = None
    reportDate = request.vars.reportDate
    if not reportDate:
        reportDate = datetime.datetime.today() - datetime.timedelta(days=1)
    else:
        reportDate = datetime.datetime.strptime(reportDate, "%Y-%m-%d")
    dtTxt = reportDate.strftime("%Y-%m-%d")
    if counterID:
        counterID = int(counterID)
        counterInfo = GetCounterInfo(counterID)
        counterSubjects = GetCounterSubjects(counterID)

    if subjectID and counterID:
        subjectID = int(subjectID)
        sql = "EXEC metric.DateCounters_Diff %s, '%s', %s, %s, '%s', %s, %s, %s" % (counterID, dtTxt, subjectID, numDays, sort, excludeCount, numRows, order)
        response.mainquery.append(sql)
        rows = dbmetrics.executesql(sql)
    return {
        "rows": rows,
        "counterInfo": counterInfo,
        "counterSubjects" : counterSubjects,
        "counterID" : counterID,
        "subjectID" : subjectID,
        "excludeCount" : excludeCount,
        "reportDate" : reportDate,
        "numDays" : numDays,
        "numRows" : numRows,
        "sort" : sort,
        "order" : order,
        "excludeCount" : excludeCount,
    }


def GetReportData(counterID, startDate, endDate):
    """
        keyID       keyText         value1      [value2]
    """
    columns = collections.OrderedDict()
    lookupText = ""
    if request.vars.filterText:
        lookupText = request.vars.filterText


    # Find the columns that we wish to show
    cc = GetCounterColumnsForCounter(counterID)
    for cID, c in cc.iteritems():
        columns[cID] = (c.columnName, c.description)

    if len(columns) == 0:
        columns[0] = ("value", None)


    orderDesc = int(not int(request.vars.orderAsc or 0))
    if request.vars.orderColumnID is None:
        orderColumnID = "NULL"
    else:
        orderColumnID = int(request.vars.orderColumnID or 0)

    sql = """EXEC zmetric.Counters_ReportData %(counterID)d, '%(startDate)s', '%(endDate)s', %(num)d, %(orderColumnID)s, %(orderDesc)d, '%(lookupText)s'""" % { 
                "counterID"     : counterID, 
                "startDate"     : startDate.strftime("%Y-%m-%d"),
                "endDate"       : endDate.strftime("%Y-%m-%d"),
                "num"           : int(request.vars.maxRows or 20),
                "orderColumnID" : orderColumnID,
                "orderDesc"     : orderDesc,
                "lookupText"    : lookupText,
              }
    response.mainquery.append(sql)
    #rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME)
    rows = dbmetrics.executesql(sql)

    report = {
        "title"   : "",
        "columns" : columns,
        "rows"    : rows,
    }

    return report


def Collection():
    pass


def AddCountToReport():
    counterID = int(request.vars.counterID)
    dt = request.vars.dt.split(" ")[0]
    columnID = int(request.vars.columnID)
    try:
        count = float(request.vars.count)
    except:
        try:
            count = int(request.vars.count)
        except:
            return "Invalid count. Please enter a number"
    key = MakeSafe(request.vars.key)

    counter = GetCounterInfo(counterID)
    keyLookupTableID = counter.keyLookupTableID
    keyID = 0
    if keyLookupTableID:
        sql = "EXEC metric.GetLookupID %d, '%s'" % (keyLookupTableID, key)
        keyID = dbmetrics.executesql(sql)[0][0]

    sql = "EXEC metric.DateCounters_InsertOrUpdate %d, '%s', %d, %s, %s" % (counterID, dt, columnID, keyID, count)
    dbmetrics.executesql(sql)

    cache.ram("keys_%s" % counterID, None, None)
    redirect(request.env.http_referer)

def SearchKeyTexts():
    term = MakeSafe(request.vars.term)
    if term:
        term = term.lower()
    counterID = int(request.vars.counterID)
    counter = GetCounterInfo(counterID)
    keyLookupTableID = counter.keyLookupTableID
    sql = "SELECT lookupText FROM zsystem.lookupValues WHERE lookupTableID = %d AND LOWER(lookupText) LIKE '%%%s%%'" % (keyLookupTableID, term)
    rows = dbmetrics.executesql(sql)
    ret = []
    for r in rows:
        e = r.lookupText
        ret.append({"id": e, "label": e, "value": e})
    return response.json(ret)

def DeleteKeyFromCounter():
    keyText = MakeSafe(request.vars.keyText)
    dt = MakeSafe(request.vars.dt)
    counterID = int(request.vars.counterID)
    counter = GetCounterInfo(counterID)
    keyLookupTableID = counter.keyLookupTableID
    keyID = 0
    if keyLookupTableID:
        sql = "SELECT lookupID FROM zsystem.lookupValues WHERE lookupTableID = %d AND LOWER(lookupText) LIKE '%s'" % (keyLookupTableID, keyText)
        rows = dbmetrics.executesql(sql)
        if not rows:
            return "Key not found"
        keyID = int(rows[0].lookupID)

    sql = "DELETE FROM zmetric.dateCounters WHERE counterID = %d AND counterDate = '%s' AND keyID = %d" % (counterID, dt, keyID)
    dbmetrics.executesql(sql)
    redirect(request.env.http_referer)

#
# Tags
#

def GetTags():
    sql = "SELECT * FROM tags ORDER BY tagName ASC"
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME_SHORT)
    return GetDictFromRowset(rows)


def GetTagIDFromName(tagName):
    sql = "SELECT tagID FROM tags WHERE tagName LIKE '%s' ORDER BY tagName ASC" % tagName
    rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME_SHORT)
    ret = None
    if rows:
        ret = rows[0].tagID
    return ret


def GetTagsForLink(linkType, linkID):
    if not linkID:
        return {}
    sql = """SELECT t.tagID, t.tagName 
               FROM tags t
                 INNER JOIN tagLinks l ON l.tagID = t.tagID
             WHERE l.linkType = %s AND l.linkID = %s AND t.tagName <> 'STARRED'
          """ % (linkType, linkID)

    #rows = cache.ram(sql, lambda:dbmetrics.executesql(sql), CACHE_TIME_SHORT)
    rows = dbmetrics.executesql(sql)
    ret = GetDictFromRowset(rows)
    return ret

def IsStarred(linkType, linkID):
    sql = """SELECT t.tagID, t.tagName 
               FROM tags t
                 INNER JOIN tagLinks l ON l.tagID = t.tagID
             WHERE l.linkType = %s AND l.linkID = %s AND t.tagName = 'STARRED'
             AND l.userName = '%s'
          """ % (linkType, linkID, session.userName)
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    b = True if len(rows) else False
    return b


@FuncTime
def AddTag():
    linkType = int(request.vars.linkType)
    linkID = int(request.vars.linkID)
    tagName = MakeSafe(request.vars.tag).capitalize().strip()
    DoAddTag(linkType, linkID, tagName)


def DoAddTag(linkType, linkID, tagName):
    tagID = GetTagIDFromName(tagName)
    if not tagID:
        sql = "INSERT INTO tags (tagName) VALUES ('%s')" % tagName
        dbmetrics.executesql(sql)
        tagID = GetTagIDFromName(tagName)

    if tagID:
        sql = "INSERT INTO tagLinks (linkType, linkID, tagID, userName) VALUES (%d, %d, %d, '%s')" % (linkType, linkID, tagID, session.userName)
        dbmetrics.executesql(sql)


@FuncTime
def RemoveTag():
    linkType = int(request.vars.linkType)
    linkID = int(request.vars.linkID)
    tagName = MakeSafe(request.vars.tag).capitalize().strip()
    DoRemoveTag(linkType, linkID, tagName)


def DoRemoveTag(linkType, linkID, tagName):
    tagID = GetTagIDFromName(tagName)
    if tagID:
        sql = "DELETE FROM tagLinks WHERE linkType = %d and linkID = %d AND tagID = %s" % (linkType, linkID, tagID)
        dbmetrics.executesql(sql)


@FuncTime
def AddStar():
    linkType = int(request.vars.linkType)
    linkID = int(request.vars.linkID)
    DoAddTag(linkType, linkID, "STARRED")


@FuncTime
def RemoveStar():
    linkType = int(request.vars.linkType)
    linkID = int(request.vars.linkID)
    DoRemoveTag(linkType, linkID, "STARRED")


def GetMyTags():
    if not session.teamName:
        return []

    sql = """
        SELECT *
          FROM tags t 
            INNER join tagLinks l ON l.tagID = t.tagID
        WHERE t.tagName <> 'STARRED' AND t.tagName LIKE '%s'
          ORDER BY t.tagName ASC
    """ % session.teamName
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    return rows


def GetMyStars():
    if not session.userName:
        return []

    sql = "EXEC metric.Tags_UserStarred '%s'" % session.userName
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    for r in rows:
        contentType = ""
        if r.linkType == TAG_REPORT:
            contentType = "COUNTER"
        elif r.linkType == TAG_COLLECTION:
            contentType = "COLLECTION"
        elif r.linkType == TAG_DASHBOARD:
            contentType = "DASHBOARD"
        r.restricted = IsRestricted(contentType, r.linkID)
    return rows


@FuncTime
def Tags():
    cond = ""
    tagNames = ""
    tagName = ""
    tags = []
    if request.vars.tag:
        tags = request.vars.tag.split("_")
        tagName = request.vars.tag.replace("_", "+")
        for t in tags:
            tagNames += "'%s', " % MakeSafe(t)
        tagNames = tagNames[:-2]

    # for multiple tags, find the intersection
    legalLinks = []
    if tagNames:
        sql = """
        SELECT linkType, linkID, COUNT(*)
          FROM tagLinks
         WHERE tagID IN (SELECT tagID FROM tags WHERE tagName IN (%s))
         GROUP BY linkType, linkID
        HAVING COUNT(*) = %s
        """ % (tagNames, len(tags))
        rows = dbmetrics.executesql(sql)
        LogQuery(sql)
        for r in rows:
            legalLinks.append([r.linkType, r.linkID])

    if request.vars.userName:
        cond += "AND l.userName = '%s'" % request.vars.userName
    sql = """
        SELECT *
          FROM tags t 
            INNER join tagLinks l ON l.tagID = t.tagID
        WHERE t.tagName <> 'STARRED' %s
          ORDER BY t.tagName ASC
    """ % cond
    LogQuery(sql)
    rows = dbmetrics.executesql(sql)
    tags = {}
    rows2 = []
    for r in rows:
        if not legalLinks or [r.linkType, r.linkID] in legalLinks:
            rows2.append(r)
    tags = GetFormattedTagsFromRows(rows2, tagName)
    return {"tags": tags}


def GetFormattedTagsFromRows(rows, tagName=None, linkType=None):
    tags = collections.OrderedDict()
    allCounters = GetCounters()
    allCollections = GetCollections()
    allMarkers = GetMarkers()
    allDashboards = GetDashboards()
    context = ""
    doneTags = []
    for r in rows:
        if not (r.linkType == linkType or not linkType):
            continue

        t = tagName or "STARRED"
        url = ""
        img = ""
        typeDesc = ""
        title = ""
        if t not in tags:
            tags[t] = []
        if r.linkType == TAG_REPORT:
            counter = allCounters.get(r.linkID, None)
            if counter:
                title = (counter.groupName or "bla") + " / " + counter.counterName
                url = A(title, _href="/Reports?counterID=%s" % counter.counterID)
                img = "tables.png"
                typeDesc = "Report"
                context = counter
        elif r.linkType == TAG_COLLECTION:
            collection = allCollections.get(r.linkID, None)
            if collection:
                title = (collection.groupName or "bla") + " / " + collection.collectionName
                url = A(title, _href="/Counters?collectionID=%s" % collection.collectionID)
                img = "chart_sml.png"
                typeDesc = "Collection"
                context = collection
        elif r.linkType == TAG_MARKER:
            marker = None
            for m in allMarkers:
                if m.markerID == r.linkID:
                    marker = m
            if marker:
                title = marker.TYPE_TITLE + " - " + marker.CATEGORY_TITLE + ": " + marker.title
                url = A(title, _href="ViewMarker?markerID=%s" % r.linkID)
                img = "flag_green.png"
                typeDesc = "Event"
                context = marker
        elif r.linkType == TAG_DASHBOARD:
            dashboard = allDashboards.get(r.linkID, None)
            if dashboard:
                title = (dashboard.dashboardName or "bla")
                url = A(title, _href="Dashboard?dashboardID=%s" % r.linkID)
                img = "gauge.png"
                typeDesc = "Dashboard"
                context = dashboard
        if title:
            k = [t, r.linkType, r.linkID]
            v = [r.linkType, r.linkID, title, url, typeDesc, img, session.userName, context]
            if k not in doneTags:
                tags[t].append(v)
                doneTags.append(k)

    for k, v in tags.iteritems():
        v.sort(key=itemgetter(2))

    return tags


def OwnerEvents():
    pass

def MakeCursor(dbname=None):
    if not dbname:
        dbname = "ebs_METRICS"
    conn = pyodbc.connect('DRIVER={SQL Server};SERVER=LOCALHOST;DATABASE=ebs_METRICS;UID=ebs_METRICS;PWD=ebs_METRICS')
    conn.autocommit = True
    curr = conn.cursor()
    return curr

@FuncTime
def SafeSQL():
    LoggedIn(True)
    response.title = "Safe SQL"
    sql = request.vars.sql
    results = None
    columns = []
    error = ""
    if sql:
        s = "zsystem.SQLSELECT '%s'" % MakeSafe(sql)
        curr = MakeCursor()
        try:
            curr.execute(s)
            results = curr.fetchall()
            columns = [c[0] for c in results[0].cursor_description]
        except Exception, e:
            error = e.args[1]

    return {
        "sql"     : sql,
        "results" : results,
        "columns" : columns,
        "error"   : error,
        }


def FetchAddToCollectionDropdown():
    return {"collections"           : GetCollections(),}

def FetchCount():
    counterID = int(request.vars.counterID or 0)
    if not counterID:
        return "No counter specified"
    subjectID = int(request.vars.subjectID or 0)
    keyID = int(request.vars.keyID or 0)
    sql = "EXEC metric.Counters_LastValue %d, NULL, %d, %d" % (counterID, subjectID, keyID)
    rows = dbmetrics.executesql(sql)
    if not rows:
        return "No rows returned. Are you sure this counterID/subjectID/keyID combination exists?"
    row = rows[0]
    return {
        "count"         : row.value,
        "counterDate"   : row.counterDate,
        "link"          : "http://%s/Counters?graph=%s_%s_%s" % (BASE_URL, counterID, subjectID, keyID),
        }

@FuncTime
def TaskLogs():
    numRows = int(request.vars.numRows or 100)
    eventID = request.vars.eventID
    text = request.vars.text or ""
    database = request.vars.db or "ebs_METRICS"
    databases = [
        ["ebs_METRICS", None],
    ]
    filt = MakeSafe(request.vars.filt)

    for d in databases:
        sql = """
            DECLARE @val varchar(MAX)
            EXEC @val = %(db)s.zsystem.Settings_Value 'zsystem', 'EventsFilter'
            SELECT @val
        """ % {"db" : d[0]}
        try:
            rows = dbmetrics.executesql(sql)
            d[1] = []
            if rows:
                v = rows[0][0]
                d[1] = [""] + v.split(",")

        except pyodbc.Error as e:
            d[1] = [("Error: %s" % str(e).split("[SQL Server]")[-1][:128]).replace("'", "\\'")]

    sql = """%(db)s.zsystem.Events_Select '%(filter)s', %(numRows)s, %(eventID)s, %(text)s""" % {
            "db"        : database,
            "filter"    : filt,
            "numRows"   : numRows,
            "eventID"   : SqlIntOrNULL(eventID),
            "text"      : ("'%s'" % text) if text else "NULL",
        }

    rows = dbmetrics.executesql(sql)
    return {
        "rows" : rows,
        "filt" : filt,
        "numRows" : numRows,
        "eventID" : eventID,
        "text"  : text,
        "database" : database,
        "databases" : databases,
        }

@FuncTime
def TaskLogsDetails():
    database = MakeSafe(request.vars.db)
    eventID = int(request.vars.eventID)
    sql = "%s.zsystem.Events_SelectByEvent %s" % (database, eventID)
    rows = dbmetrics.executesql(sql)
    event = None
    for r in rows:
        if r.eventID == eventID:
            event = r
    return {
        "rows"     : rows,
        "event"    : event,
        "database" : database,
        "eventID"  : eventID
    }


def ListImages():
    def IsImage(f):
        if f.lower().endswith(".png"):
            return True
        if f.lower().endswith(".jpg"):
            return True
        return False

    folder = "TargitImages"
    if request.vars.folder:
        folder = request.vars.folder
    fullPath = os.path.join("applications/evemetrics/static/images", folder)
    images = []
    for root, dirs, files in os.walk(fullPath):
        p = root.split("/images")[1].replace("\\", "/")
        for f in files:
            if IsImage(f):
                f = p + "/" + f
                f = URL("static/images%s" % f)
                images.append(f)
    images.sort()
    return {"images": images, "folder": folder}

@FuncTime
def ComparePeriods():
    counterID = 9
    subjectID = 0
    keyID = 0
    days = 90
    daysBefore = 7
    doNotSubtractStartValue = 0
    startDate = request.vars.startDate or None
    if not startDate:
        startDate = (datetime.datetime.now()-datetime.timedelta(days=365*8)).strftime("%Y-%m-%d")
    endDate = request.vars.endDate or None
    counterID = int(request.vars.counterID or counterID)
    subjectID = int(request.vars.subjectID or subjectID)
    keyID = int(request.vars.keyID or keyID)
    days = int(request.vars.days or days)
    daysBefore = int(request.vars.daysBefore or daysBefore)
    doNotSubtractStartValue = int(request.vars.doNotSubtractStartValue or doNotSubtractStartValue)
    title = ""
    counter = GetCounterInfo(counterID)
    subjectText, keyText = GetGraphText(counterID, subjectID, keyID)
    sql = """
SET NOCOUNT ON
DECLARE @counterID int = %(counterID)s
DECLARE @subjectID int = %(subjectID)s
DECLARE @keyID int = %(keyID)s
DECLARE @firstValue float

DECLARE @dt datetime
DECLARE @title varchar(50)
DECLARE @results TABLE (dt date , title varchar(50), dayNumber int, [value] float)
DECLARE @cursor CURSOR 
SET @cursor = CURSOR LOCAL FAST_FORWARD
  FOR SELECT [dateTime], title FROM markers m WHERE m.categoryID = 1 AND m.typeID = 1 AND [dateTime] BETWEEN '%(startDate)s' AND '%(endDate)s' ORDER BY [dateTime]
OPEN @cursor
FETCH NEXT FROM @cursor INTO @dt, @title
WHILE @@FETCH_STATUS = 0
BEGIN
  SELECT TOP 1 @firstValue = value FROM zmetric.dateCounters c WHERE c.counterID = @counterID AND c.subjectID = @subjectID AND c.keyID = @keyID AND c.counterDate >= @dt ORDER BY c.counterDate ASC
  INSERT INTO @results (dt, title, dayNumber, [value])
    SELECT @dt, @title, DATEDIFF(d, @dt, counterDate), value-%(subtractFirst)s FROM zmetric.dateCounters c WHERE c.counterID = @counterID AND c.subjectID = @subjectID AND c.keyID = @keyID AND c.counterDate BETWEEN DATEADD(d, -%(daysBefore)s, @dt) AND DATEADD(d, %(days)s, @dt) ORDER BY c.counterDate ASC
  FETCH NEXT FROM @cursor INTO @dt, @title
END
CLOSE @cursor
DEALLOCATE @cursor
SELECT * FROM @results ORDER BY dt, title, dayNumber
    """ % {
        "counterID": counterID,
        "subjectID": subjectID,
        "keyID": keyID,
        "days" : days,
        "daysBefore" : daysBefore,
        "subtractFirst" : "0" if doNotSubtractStartValue else "@firstValue",
        "startDate": startDate,
        "endDate": endDate or (datetime.datetime.now()).strftime("%Y-%m-%d"),
    }
    response.mainquery.append(sql)
    curr = MakeCursor("ebs_METRICS")
    curr.execute(sql)
    rows = curr.fetchall()
    series = collections.OrderedDict()
    for r in rows:
        k = (r.title, r.dt)
        if k not in series:
            series[k] = []
        series[k].append((r.dayNumber, r.value))
    return {
        "rows"      : rows,
        "series"    : series,
        "counterID" : counterID,
        "counter"   : counter,
        "subjectID" : subjectID,
        "keyID"     : keyID,
        "days"      : days,
        "daysBefore"      : daysBefore,
        "doNotSubtractStartValue" : doNotSubtractStartValue,
        "title"     : title,
        "subjectText" : subjectText,
        "keyText"   : keyText,
        "startDate" : startDate,
        "endDate"   : endDate,
    }

@FuncTime
def index():
    """
    example action using the internationalization operator T and flash
    rendered by views/default/index.html or views/generic.html
    """
    #response.flash = "Welcome to EVE Metrics!"
    response.title = SITE_TITLE
    if IsLocal():
        session.userName = "nonnib"
    message = ""
    stars = GetFormattedTagsFromRows(GetMyStars())
    starredDashboards = GetFormattedTagsFromRows(GetMyStars(), linkType=TAG_DASHBOARD)
    starredCollections = GetFormattedTagsFromRows(GetMyStars(), linkType=TAG_COLLECTION)
    starredReports = GetFormattedTagsFromRows(GetMyStars(), linkType=TAG_REPORT)
    starredMarkers = GetFormattedTagsFromRows(GetMyStars(), linkType=TAG_MARKER)
    tags = GetFormattedTagsFromRows(GetMyTags())
    return dict(
        message=XML(message),
        tags=tags,
        starredDashboards = starredDashboards,
        starredCollections = starredCollections,
        starredReports = starredReports,
        starredMarkers = starredMarkers,
        )

def user():
    """
    exposes:
    http://..../[app]/default/user/login
    http://..../[app]/default/user/logout
    http://..../[app]/default/user/register
    http://..../[app]/default/user/profile
    http://..../[app]/default/user/retrieve_password
    http://..../[app]/default/user/change_password
    use @auth.requires_login()
        @auth.requires_membership('group name')
        @auth.requires_permission('read','table name',record_id)
    to decorate functions that need access control
    """
    return dict(form=auth())


def download():
    """
    allows downloading of uploaded files
    http://..../[app]/default/download/[filename]
    """
    return response.download(request,db)


def call():
    """
    exposes services. for example:
    http://..../[app]/default/call/jsonrpc
    decorate with @services.jsonrpc the functions to expose
    supports xml, json, xmlrpc, jsonrpc, amfrpc, rss, csv
    """
    return service()
