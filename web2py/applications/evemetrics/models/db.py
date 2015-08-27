# -*- coding: utf-8 -*-

import collections
from collections import OrderedDict
import operator
import datetime
import re, os, sys, copy
import types
import pyodbc
import json

import logging
logger = logging.getLogger("web2py.app.evemetrics")
logger.setLevel(logging.WARN)

def FmtDate(dt):
    return dt.strftime("%Y-%m-%d")

def RedirectPrintToLog(logName):
    logFileName = os.path.join("logs", "%s_%s_stdout.log" % (logName, FmtDate(datetime.datetime.today())))
    sys.stdout = open(logFileName, "a")
    logFileName = os.path.join("logs", "%s_%s_stderr.log" % (logName, FmtDate(datetime.datetime.today())))
    sys.stderr = open(logFileName, "a")

def IsLocal():
    return "127.0.0.1" in request.client.lower()

if not IsLocal():
    RedirectPrintToLog("evemetrics")

response.query = []
response.mainquery = []

LOGO_IMAGE = "static/images/eve2.png"
SITE_TITLE = "Metrics"
BASE_URL = "metrics"

DEFAULT_CHART_COLORS = ["3366cc","dc3912","ff9900","109618","990099","0099c6","dd4477","66aa00","b82e2e","316395","994499","22aa99","aaaa11","6633cc","e67300","8b0707","651067","329262","5574a6","3b3eac","b77322","16d620","b91383","f4359e","9c5935","a9c413","2a778d","668d1c","bea413","0c5922","743411", "000000", "555555", "999999"]
DEFAULT_CHART_LINEWIDTH = 2
DEFAULT_CHART_POINTSIZE = 0

MAX_DIGEST_SECTIONS = 10
MAX_DIGEST_ALERTS   = 50

# Access restrictions
ACCESS_OPEN             = None
ACCESS_GRANTED          = 0
ACCESS_DENIED           = 1
ACCESS_DENIED_LOGGEDOUT = 2

ACCESS_SECRET           = "SECRET!"
db = SQLDB('mssql://ebs_METRICS:ebs_METRICS@LOCALHOST/ebs_METRICS', check_reserved=['mssql'])

response.generic_patterns = ['*'] # to allow generic views

from gluon.tools import Auth, Crud, Service, PluginManager, prettydate
auth = None#Auth(db, hmac_key=Auth.get_or_create_key())
crud, service, plugins = Crud(db), Service(), PluginManager()

mail = None


TAG_REPORT      = 1
TAG_COLLECTION  = 2
TAG_MARKER      = 3
TAG_DASHBOARD   = 4
TAG_DIGEST      = 5

CACHE_TIME = 60 * 30 # cache for 30 minutes !!
CACHE_TIME_FOREVER = 60 * 60 * 24
CACHE_TIME_SHORT = 60 # cache for 1 minute

ADMIN_PASSWORD = "changeme"

dbmetrics = SQLDB('mssql://ebs_METRICS:ebs_METRICS@LOCALHOST/ebs_METRICS', check_reserved=['mssql'])


def GetAccessRules():
    rules = cache.ram("accessRules", lambda:DoGetAccessRules(), CACHE_TIME)
    #rules = DoGetAccessRules()
    return rules

def DoGetAccessRules():
    sql = "SELECT ownerUserName='', * FROM metric.accessRules"
    rows = dbmetrics.executesql(sql)
    rules = {}
    counters = GetCounters()
    sql = "SELECT digestID, userName FROM metric.digests"
    digests = {}
    for r in dbmetrics.executesql(sql):
        digests[r.digestID] = r.userName
    sql = "SELECT collectionID, userName FROM metric.collections"
    collections = {}
    for r in dbmetrics.executesql(sql):
        collections[r.collectionID] = r.userName
    sql = "SELECT dashboardID, userName FROM metric.dashboards"
    dashboards = {}
    for r in dbmetrics.executesql(sql):
        dashboards[r.dashboardID] = r.userName

    for r in rows:
        k = (r.contentType, r.contentID)
        if k not in rules:
            rules[k] = []
        if r.contentType == "COUNTER":
            r.ownerUserName = counters[r.contentID].userName
        elif r.contentType == "DIGEST":
            r.ownerUserName = digests.get(r.contentID, "")
        elif r.contentType == "COLLECTION":
            r.ownerUserName = collections.get(r.contentID, "")
        elif r.contentType == "DASHBOARD":
            r.ownerUserName = dashboards.get(r.contentID, "")
        rules[k].append(r)
    return rules

def IsRestricted(contentType, contentID):
    if request.vars.secret == ACCESS_SECRET or session.secret == ACCESS_SECRET:
        return ACCESS_OPEN

    rules = GetAccessRules()
    k = (contentType, contentID)

    if k not in rules:
        return ACCESS_OPEN

    if not session.userName:
        return ACCESS_DENIED_LOGGEDOUT
    for r in rules[k]:
        if r.emailAddress.lower() == session.emailAddress.lower():
            return ACCESS_GRANTED
        if r.mailingList and r.fullName in session.groups:
            return ACCESS_GRANTED
    return ACCESS_DENIED


def FmtDatePretty(dt):
    return dt.strftime("%A, %b %d. %Y")

def FmtAmtInt(amt):
    amt = amt or 0
    locale.setlocale(locale.LC_ALL, 'UK')
    return locale.format("%.0f", amt, grouping=True)

def FmtAmtSmart(amt):
    amt = amt or 0
    locale.setlocale(locale.LC_ALL, 'UK')
    fmt = "%.0f"
    if amt > 0 and amt < 10:
        fmt = "%.1f"
    return locale.format(fmt, amt, grouping=True)

def FmtAmt(amt, decimalMap={0.0: "%.2f", 1000000.0: "%.0f"}):
    amt = amt or 0
    locale.setlocale(locale.LC_ALL, 'UK')
    if int(round(amt, 0) * 100.0) == int(round(amt*100.0, 0)): # always show no digits on whole ints
        fmt = "%.0f"
    else:
        lastNumDecimals = 4
        for val in sorted(decimalMap.keys()):
            numDecimals = decimalMap[val]
            if amt < val:
                fmt = lastNumDecimals
                break
            lastNumDecimals = numDecimals
        else:
            fmt = lastNumDecimals
    try:
        return locale.format(fmt, amt, grouping=True)
    except:
        return amt


def HistoryLink(txt, counterID, subjectID, keyID):
    if keyID is not None:
        url = "Counters?graph=%s_%s_%s" % (counterID, subjectID, keyID)
    else:
        url = "Counters?graph=%s_%s" % (counterID, subjectID)
    return A(txt, _href=URL(url))


def CutAt(txt, l):
    if len(txt) <= l:
        return txt
    ret = txt[:l] + "..."
    return ret

def CutAtWithTooltip(txt, l):
    if len(txt) <= l:
        return txt
    ret = txt[:l] + "..."
    ret = SPAN(ret, _title=txt)
    return ret

def MakePrettySQL(sql):
    if not sql:
        return sql
    s = sql.replace("  ", "")
    s = s.replace("\n ", "\n")
    s = s.replace("FROM",       "  FROM")
    s = s.replace("WHERE",      " WHERE")
    s = s.replace("ORDER BY",   " ORDER BY")
    s = s.replace("GROUP BY",   " GROUP BY")
    s = s.replace("LEFT JOIN",  "    LEFT JOIN")
    s = s.replace("INNER JOIN", "    INNER JOIN")
    s = s.replace(" VALUES ",   "     VALUES ")
    return s


def MakePrettySQLOld(sql):

    s = sql
    s = s.replace(";\n", ";<br>")
    s = s.replace("\n", "<br>")
    s = s.replace("FROM", "<span class=sql>&nbsp;&nbsp;FROM</span>")
    s = s.replace("WHERE", "<span class=sql>&nbsp;WHERE</span>")
    s = s.replace("ORDER BY", "<span class=sql>&nbsp;ORDER BY</span>")
    s = s.replace("GROUP BY", "<span class=sql>&nbsp;GROUP BY</span>")
    s = s.replace("(SELECT", "(<span class=sql>SELECT</span>")
    s = s.replace("SELECT", "<span class=sql>SELECT</span>")
    s = s.replace("UPDATE", "<span class=sql>UPDATE</span>")
    s = s.replace("EXEC", "<span class=sql>EXEC</span>")
    s = s.replace("INSERT INTO", "<span class=sql>INSERT INTO</span>")
    s = s.replace("LEFT JOIN", "<span class=sql>&nbsp;&nbsp;&nbsp;&nbsp;LEFT JOIN</span>")
    s = s.replace("INNER JOIN", "<span class=sql>&nbsp;&nbsp;&nbsp;&nbsp;INNER JOIN</span>")
    s = s.replace(" VALUES ", "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span class=sql>VALUES</span> ")

    s = s.replace("SET ", "<span class=sql2>SET</span> ")
    s = s.replace(" ON ", " <span class=sql2>ON</span> ")
    s = s.replace(" ASC", " <span class=sql2>ASC</span>")
    s = s.replace(" DESC", " <span class=sql2>DESC</span>")
    s = s.replace(" AS ", " <span class=sql2>AS</span> ")
    s = s.replace(" AND ", " <span class=sql2>AND</span> ")
    s = s.replace(" OR ", " <span class=sql2>OR</span> ")
    s = s.replace(" NOT ", " <span class=sql2>NOT</span> ")
    s = s.replace("COUNT(", "<span class=sql2>COUNT</span>(")
    s = s.replace("SUM(", "<span class=sql2>SUM</span>(")
    s = s.replace(" UNION ALL ", "<span class=sql>UNION ALL</span><br>")
    s = s.replace(" UNION ", "<span class=sql>UNION</span><br>")
    return s


def GetFullUrl():
    url = (request.env.web2py_original_uri or "")
    if url.endswith("?"):
        pass
    elif url.endswith("&"):
        pass
    else:
        if "?" in url:
            url += "&"
        else:
            url += "?"
    return url

def GetMethod():
    return request.env.web2py_original_uri.split("?")[0].split("/")[1]

def GetFullUrlWithout(k):
    klst = k.split("&")
    url = request.env.web2py_original_uri
    lst = url.split("?")
    if len(lst) < 2:
        return url + "?"
    args = (lst[1] or "").split("&")

    lst[1] = ""
    for a in args:
        skip = False
        for kk in klst:
            if a.lower().startswith(kk.lower()):
                skip = True

        if not skip:
            lst[1] += a + "&"
    
    ret = lst[0] + "?" + lst[1]
    ret = ret.replace("&&", "&")
    return ret

def MakeSafe(r):
    if r:
        r = r.replace("'", "''")
    else:
        r = ""
    return r


def GetUserName(userID):
    return cache.ram("user_%s" % userID, lambda:DoGetUserName(userID), CACHE_TIME_FOREVER)

def DoGetUserName(userID):
    sql = "SELECT name = first_name + ' ' + last_name, email FROM auth_user WHERE id = %d" % int(userID)
    ret = ("Unknown", "Unknown")
    rows = dbmetrics.executesql(sql)
    if rows:
        ret = rows[0]
    return ret


def SetCookie(name, value):
    response.cookies[name] = value
    response.cookies[name]["expires"] = 365 * 24 * 3600
    response.cookies[name]["path"] = "/"


def GetCookie(name):
    try:
        return request.cookies[name].value
    except:
        return None

def DeleteCookie(name):
    response.cookies[name]["expires"] = -10


class KeyVal:

    __guid__ = "util.KeyVal"
    __passbyvalue__ = 1

    def __init__(self, dictLikeObject=None, **kw):
        self.__dict__ = kw
        if dictLikeObject is not None:
            if isinstance(dictLikeObject, dict):
                self.__dict__.update(dictLikeObject)
            elif isinstance(dictLikeObject, blue.DBRow):
                for k in dictLikeObject.__keys__:
                    self.__dict__[k] = getattr(dictLikeObject, k)
            elif isinstance(dictLikeObject, KeyVal):
                self.__dict__.update(dictLikeObject.__dict__)
            else:
                raise TypeError("%s can only be initialized with dictionaries, key/value pairs or blue.DBRow's. %s isn't one of them." % (self.__guid__, type(dictLikeObject)))
            

    def __str__(self):
        members = dict(filter(lambda (k, v): not k.startswith("__"), self.__dict__.items()))
        return "%s %s: %s" % (self.__doc__ or "Anonymous", self.__class__.__name__, members)

    def __repr__(self):
        return "<%s>" % str(self)

    def copy(self):
        ret = KeyVal()
        ret.__dict__.update(self.__dict__)
        return ret

    def get(self, key, defval=None):
        return self.__dict__.get(key, defval)

    def Get(self, key, defval=None):
        return self.__dict__.get(key, defval)

    def Set(self, key, value):
        self.__dict__[key] = value 


def WriteStar(starred):
    y = "n"
    if starred: y = "y"
    star = URL("static/images/watched_%s.gif" % y)
    return XML("<img class=link id=starimg src=\"%s\" OnClick=\"ToggleStar();\" title=\"Click to mark starred\"> " % star)

def WriteCounterLink(counter):
    n = ""
    txt = ""
    desc = "<span class=ttcrea>Created at %s by %s</span>" % (FmtDate(counter.createDate), counter.userName)
    if counter.createDate > datetime.datetime.now()-datetime.timedelta(days=14):
        n = " <i><font color=green>new!</font></i>"
    if not counter.published:
        n = " <i><font color=crimson title=\"This counter is running against a test server and is yet to be published to TQ\">unpublised</font></i>"
    res = ""
    if getattr(counter, "restricted", None) == ACCESS_GRANTED:
        res = " <img title=\"This page is access restricted and you have access\" src=\"%s\" style=\"vertical-align:middle;\">" % (URL("static/images/lock.png"))
    txt = "<a class=tt href=\"Report?counterID=%s\" title=\"%s<br>%s\">%s</a>%s%s" % (counter.counterID, FmtText(counter.description).replace('"', '').replace("\r", ""), desc, counter.counterName, n, res)
    return XML(txt)

def WriteCollectionLink(collection):
    n = ""
    txt = ""
    desc = collection.description or ""
    if desc: desc += "<br>"
    desc = FmtText(desc)
    desc += "<span class=ttcrea>Created at %s by %s</span>" % (FmtDate(collection.createDate), collection.userName)
    if collection.createDate > datetime.datetime.now()-datetime.timedelta(days=14):
        n = " <i><font color=green>new!</font></i>"
    txt = "<a class=tt href=\"Collections?collectionID=%s\" title=\"%s\">%s</a>%s" % (collection.collectionID, desc, collection.collectionName or "Unnamed", n)
    return XML(txt)

def WriteDashboardLink(dashboard):
    n = ""
    txt = ""
    desc = dashboard.description or ""
    if desc: desc += "<br>"
    desc = FmtText(desc)
    desc += "<span class=ttcrea>Created at %s by %s</span>" % (FmtDate(dashboard.createDate), dashboard.userName)
    if dashboard.createDate > datetime.datetime.now()-datetime.timedelta(days=14):
        n = " <i><font color=green>new!</font></i>"
    txt = "<a class=tt href=\"Dashboard?dashboardID=%s\" title=\"%s\">%s</a>%s" % (dashboard.dashboardID, desc, dashboard.dashboardName or "Unnamed", n)
    return XML(txt)

def WriteExportToExcel(elementID):
    txt = "<div style=\"text-align:right; margin-top:-5px; margin-right:5px;\"><span OnClick=\"exportToExcel('%s');\" class=\"link smalltext\">Export to Excel</span></div>" % elementID
    return XML(txt)

def FmtText(txt):
    txt = (txt or "").replace("\n", "<br>")
    return txt

def FmtText2(txt):
    txt = txt.replace("\n", "<br>")
    txt = txt.replace("\r", "")
    smilies = {
        "o:)"   : "em_angel.gif",
        "O:)"   : "em_angel.gif",
        "O:-)"  : "em_angel.gif",
        "o:-)"  : "em_angel.gif",

        ":)"    : "em_smile.gif",
        ":-)"   : "em_smile.gif",

        ";)"    : "em_wink.gif",
        ";-)"   : "em_wink.gif",

        ":D"    : "em_wide.gif",
        ":-D"   : "em_wide.gif",

        ":("    : "em_sad.gif",
        ":-("   : "em_sad.gif",

        ":'("   : "em_cry.gif",
        ":'-("  : "em_cry.gif",

        ":-S"   : "em_confused.gif",
        ":-s"   : "em_confused.gif",
        ":S"    : "em_confused.gif",
        ":s"    : "em_confused.gif",

        ":O"    : "em_surprised.gif",
        ":-O"   : "em_surprised.gif",
        ":o"    : "em_surprised.gif",
        ":-o"   : "em_surprised.gif",

        ":|"    : "em_shocked.gif",
        ":-|"   : "em_shocked.gif",

        ":-$"   : "em_ashamed.gif",
        ":$"    : "em_ashamed.gif",

        ":-p"   : "em_tongue.gif",
        ":p"    : "em_tongue.gif",
        ":-P"   : "em_tongue.gif",
        ":P"    : "em_tongue.gif",

        ":-@"   : "em_mad.gif",
        ":@"    : "em_mad.gif",

        "%-)"   : "sml_dvl.gif",

        "(*)"   : "em_star.gif",

        "S-|"   : "em_dizzy.gif",

        "B-)"   : "em_shades.gif",

        ":-%"   : "em_ill.gif",

        ";-("   : "em_scrooge.gif",
    }

    formatting = {
        "[b]"   : "<strong>",
        "[/b]"  : "</strong>",
        "[i]"   : "<em>",
        "[/i]"  : "</em>",
        "[c]"   : "<center>",
        "[/c]"  : "</center>",
        "[/col]"  : "</font>",
        "[colB]"  : "<font color=blue>",
        "[colR]"  : "<font color=crimson>",
        "[colY]"  : "<font color=orange>",
        "[colG]"  : "<font color=green>",
        "[colGr]"  : "<font color=gray>",
        "[/url]"  : "</a>",
    }
    for s, img in smilies.iteritems():
        txt = txt.replace(s, "<img src=\"%s\">" % URL("static/images/" + img))

    for s, f in formatting.iteritems():
        txt = txt.replace(s, f)

    urlPattern = "\[url=(.*?)\]"
    txt = re.sub(urlPattern, "<a href=\"\g<1>\">", txt)
    return txt


def GetPrettyValueForGoal(goal, goalDirection, goalType):
    goal = "%.1f" % (goal or 0)
    goalSelector = (goalDirection or "U") + (goalType or "V")
    v = ""
    if goalSelector == "UV":
        v = "Value should be increasing"
    elif goalSelector == "DV":
        v = "Value should be decreasing"
    elif goalSelector == "SP":
        v = "Value should be stable within " + goal + " %"
    elif goalSelector == "AV":
        v = "Value should be be above " + goal
    elif goalSelector == "BV":
        v = "Value should be be below " + goal
    elif goalSelector == "AP":
        v = "Value should increase weekly by " + goal + " %"
    elif goalSelector == "BP":
        v = "Value should decrease weekly by " + goal + " %"
    return v

def GetPrettyDashboardAggregateFunction(func):
    d = {
        "MIN"  : "Minimum value",
        "MAX"  : "Maximum value",
        "LAST"  : "Last value",
        "SUM"  : "Sum",
        "AVG"  : "Average value",
        "FIRST": "First value",
    }
    return d.get(func, "Unknown")

    """
    <option value="UV">Value should be increasing</option>
    <option value="DV">Value should be decreasing</option>

    <option value="SP">Value should be stable within a %</option>

    <option value="AV">Value should be above a certain value</option>
    <option value="BV">Value should be below a certain value</option>

    <option value="AP">Value should increase by %</option>
    <option value="BP">Value should decrease by %</option>
    """

def GroupAndName(groupID, groupName, title, url):
    txt = title
    if groupID:
        txt = "<a href=\"%s?groupID=%s\">%s</a> / %s" % (url, groupID, groupName, title)
    return XML(txt)

def GetDashboardArrow(row, includeValue=False, reverse=False, compareCol=2, justDot=False, numDays=None):
    severityThreshold = row.severityThreshold or 5.0
    goalDirection = row.goalDirection or "U"
    goal = row.goal or 0.0
    goalType = row.goalType or "V"
    goalSelector = goalDirection + goalType
    if numDays and (row.aggregateFunction or "AVG") == "SUM" and (goalSelector == "AV" or goalSelector == "BV"):
        goal *= numDays
    severityThreshold /= 100
    otherVal = getattr(row, "value%s" % compareCol)
    if not otherVal:
        otherVal = row.value1
    val1 = int("%.0f" % (row.value1 or 0))
    val2 = int("%.0f" % (otherVal or 0))
    diff = ((row.value1 or 0.0) - (otherVal or 0.0)) / (row.value1 or 1.0)
    direction = 0
    d = "Up"
    g = "Neutral"
    tt = ""
    col = "yellow"

    if val1 > val2:
        direction = 1
    elif row.value1 < val2:
        direction = -1
    if direction != 0:
        if abs(diff) < (severityThreshold)/10.0:
            direction = 0
    minorChange = False
    whichdir = ""
    if abs(diff) < severityThreshold:
        minorChange = True
    if goalSelector == "AP":
        goalSelector = "UV"
    if goalSelector == "BP":
        goalSelector = "DV"
    if goalSelector == "NN":
        whichdir = ""
        if direction == 0:
            d = "Even"
            whichdir = "changed"
        elif direction == 1:
            d = "Up"
            g = "Neutral"
            whichdir = "increased"
        else:
            d = "Down"
            g = "Neutral"
            whichdir = "decreased"
        if minorChange and d != "Even":
            d += "_Slightly"
        tt = "No goal\nValue %s by %.1f%%" % (whichdir, abs(diff)*100.0)
    if goalSelector == "UV": # Value should be increasing
        whichdir = ""
        if direction == 0:
            d = "Even"
            whichdir = "changed"
        elif direction == 1:
            d = "Up"
            g = "Good"
            whichdir = "increased"
        else:
            d = "Down"
            g = "Bad"
            whichdir = "decreased"
        if minorChange and d != "Even":
            d += "_Slightly"
        tt = "Value should always increase\nValue %s by %.1f%%" % (whichdir, abs(diff)*100.0)
    elif goalSelector == "DV": # Value should be decreasing
        whichdir = ""
        if direction == 0:
            d = "Even"
            whichdir = "changed"
        elif direction == 1:
            d = "Up"
            g = "Bad"
            whichdir = "increased"
        else:
            d = "Down"
            g = "Good"
            whichdir = "decreased"
        if minorChange and d != "Even":
            d += "_Slightly"
            whichdir += " slightly"
        tt = "Value should always decrease\nValue %s by %.1f%%" % (whichdir, abs(diff)*100.0)

    elif goalSelector == "SP": # Value should be stable within a %
        whichdir = ""
        if direction == 0:
            d = "Even"
            whichdir = "changed"
        elif direction == 1:
            d = "Up"
            g = "Bad"
            whichdir = "increased"
        else:
            d = "Down"
            g = "Bad"
            whichdir = "decreased"
        if abs(diff) < goal / 100.0:
            g = "Neutral"
        if minorChange and d != "Even":
            d += "_Slightly"
            whichdir += " slightly"

        tt = "Value should be stable between +- %s%%\nValue %s by %.1f%%" % (goal, whichdir, abs(diff)*100.0)

    elif goalSelector == "AV": # Value should be above a certain value
        g = "Good"
        if direction == 0:
            d = "Even"
        elif direction == 1:
            d = "Up"
        else:
            d = "Down"
        if minorChange and d != "Even":
            d += "_Slightly"
            whichdir += " slightly"
        if val1 < goal:
            g = "Bad"
            if val1 > goal - goal * severityThreshold: 
                g = "Neutral"
        tt = "Value should always be above %s\nValue is at %s" % (goal, val1)

    elif goalSelector == "BV": # Value should be below a certain value
        g = "Good"
        if direction == 0:
            d = "Even"
        elif direction == 1:
            d = "Up"
        else:
            d = "Down"
        if minorChange and d != "Even":
            d += "_Slightly"
            whichdir += " slightly"
        if val1 > goal:
            g = "Bad"
            if val1 < goal + goal * severityThreshold: 
                g = "Neutral"
        tt = "Value should always be below %s\nValue is at %s" % (goal, val1)
    elif goalSelector == "AP": # Value should decrease by % every week
        pass
    elif goalSelector == "BP": # Value should increase by % every week
        pass
    if goalSelector == "NA":
        return XML("&nbsp;")
    r = ""
    if reverse:
        r = "transform: scaleX(-1)"
    if justDot: d = "dot"
    ret = "<img class=tt title=\"%s\" src=\"%s\" width=16 style=\"margin-bottom:-1px;%s\">" % (tt, URL(r"static/images/kpi_%s_%s_24.png" % (d, g)), r)
    if includeValue:
        col = "black"
        if goalSelector in ("AV", "BV"):
            ret += "<span style=\"color:#AAAAAA;font-size:14px;\"> %s</span>" % FmtAmt(goal)
        else:
            if g == "Bad": col = "crimson"
            if g == "Good": col = "green"
            a = abs(diff)*100.0
            if a > 10:
                a = "%.0f" % a
            else:
                a = "%.1f" % a
            ret += "<font color=%s> %s%%</font>" % (col, a)
    return XML(ret)

def GetCurrentUrlFieldsWithout(lst):
    vars = request.vars.copy()
    remList = []
    for thisVar in vars:
        if thisVar in lst:
            remList.append(thisVar)
    for valToRemove in remList:
        del vars[valToRemove]
    return vars

def GetCurrentUrlWithout(k):
    vars = GetCurrentUrlFieldsWithout(k.split(","))
    url = URL(r=request, f='', vars=vars)
    if len(vars) == 0:
        return url + "?"
    else:
        return url + "&"

def GetUrlForSubjectOrKey(i, txt, link, label):
    if not link: link = ""
    if not txt: txt = ""
    if link and ")s" not in link: link += "%(lookupID)s" # backwards compatible
    link = link % {"lookupID": i, "lookupText": txt}
    if not label: label = "%(lookupText)s"
    label = label % {"lookupID": i, "lookupText": txt}
    ret = label
    if link:
        ret = A(label, _class="faintlink", _href=link, _title=link, _target="ext")
    return ret