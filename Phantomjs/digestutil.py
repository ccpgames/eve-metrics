import smtplib, subprocess, uuid, os, sys, datetime, json, getopt, urllib2, traceback, locale
import xml.dom.minidom as minidom

from PIL import Image
import pyodbc
import logging

SMTP_SERVER = "SMTP"
SAVE_IMG_PATH = "..\\web2py\\applications\\evemetrics\\static\\images\\digest\\"
SENDER = "EVE Metrics Digest <evemetricsdigest@ccpgames.com>"
ERROR_EMAIL_ADDRESS = "digesterror@ccpgames.com"
MAX_IMAGE_HEIGHT = 2000

BASE_URL = "http://evemetrics/"

def MakeCursor():
    conn = pyodbc.connect('DRIVER={SQL Server};SERVER=LOCALHOST;DATABASE=ebs_METRICS;UID=ebs_METRICS;PWD=ebs_METRICS')
    conn.autocommit = True
    curr = conn.cursor()
    return curr

def ConnectToMetricsDB():
    return MakeCursor()

def SqlIntOrNULL(v):
    if v is not None:
        return "%d" % v
    else:
        return "NULL"

def SqlDateOrNULL(v):
    if v:
        return "'%s'" % v.replace(".", "-")
    else:
        return "NULL"

def SendEmail(email, title, body):
    sender = "evemetrics@ccpgames.com"
    receivers = email.split(",")
    body = body.encode("UTF-8", errors="replace")
    message = """From: Eve Metrics <%(emailcc)s>
To: %(email)s
MIME-Version: 1.0
Content-type: text/html
Subject: %(title)s

%(body)s
""" % {"emailcc": sender, "body": body, "email": str(email), "title": title}
    try:
        smtpObj = smtplib.SMTP(SMTP_SERVER)
        #smtpObj.set_debuglevel(True)
        smtpObj.sendmail(sender, receivers, message)         
        logging.info("Successfully sent email to %s" % receivers[0])
    except Exception, e:
        logging.error("Error: unable to send email to %s: %s" % (receivers[0], e))
        raise

def H3(txt):
    return "<h3 style=\"font-size:18px;font-family: Verdana;\">%s</h3>" % txt

def A(url, txt, _style=None):
    return "<a style=\"font-family: Verdana;text-decoration:none; %s\" href=\"%s%s\">%s</a>" % (_style or "", BASE_URL, url, txt)

def SplitImage(imgName):
    maxHeight = MAX_IMAGE_HEIGHT / 2 # split into 1000px segments
    images = []
    imagePath = "%s%s" % (SAVE_IMG_PATH, imgName)
    imageHandle = Image.open(imagePath)
    w, h = imageHandle.size
    numParts = h / float(maxHeight)
    logging.info("Image is %s px high but max height is %s px. I will split %s into %s parts" % (h, maxHeight, imagePath, numParts))
    pos = 0
    while pos < h:
        box = (0, pos, w, min(h, pos+maxHeight))
        logging.debug("box is %s" % repr(box))
        croppedImg = imageHandle.crop(box)
        croppedImageName = imgName.replace(".png", "-%s.png" % pos)
        croppedImagePath = "%s%s" % (SAVE_IMG_PATH, croppedImageName)
        croppedImg.save(croppedImagePath)
        pos += maxHeight
        images.append(croppedImageName)
    return images

def FmtAmtSmart(amt):
    amt = amt or 0
    locale.setlocale(locale.LC_ALL, 'UK')
    fmt = "%.0f"
    if amt > 0 and amt < 10:
        fmt = "%.1f"
    return locale.format(fmt, amt, grouping=True)

def GetEveMetricsError():
    url = "%sFetchCount?counterID=9&subjectID=0&rss=1&raw=1" % BASE_URL # subscriber count
    try:
        response = urllib2.urlopen(url)
    except urllib2.URLError as e:
        error = "Error talking to server %s: %s" % (url, e.reason)
        return error
    except urllib2.HTTPError as e:
        error = "Failed to load %s: %s" % (url, e.code)
        return error
    try:
        html = response.read()
        doc = minidom.parseString(html)
        items = doc.getElementsByTagName("item")

        item = items[0]
        obj = item.getElementsByTagName("title")[0]
        count = int(float(obj.childNodes[0].nodeValue))
        obj = item.getElementsByTagName("pubDate")[0]
        dt = datetime.datetime.strptime(obj.childNodes[0].nodeValue, "%Y-%m-%d")
        yesterday = datetime.datetime.today() - datetime.timedelta(days=1)
        yesterday = yesterday.replace(hour=0, minute=0, second=0, microsecond=0)
        if dt < yesterday:
            error = "Date returned from %s is too old: %s vs %s" % (url, dt, yesterday)
            return error
    except Exception as e:
        error = "Error parsing rss feed from %s: %s" % (url, e)
        return error

    return None

def LogTaskStarted(taskName, eventText="", int_1=None, int_2=None, int_3=None, int_4=None, int_5=None, int_6=None, int_7=None, int_8=None, int_9=None, date_1=None, fixedText=None, parentID=None):
    curr = ConnectToMetricsDB()
    fixedTextSql = "NULL"
    if fixedText:
        fixedTextSql = "'%s'" % (fixedText or "").replace("'", "''")
    sql = """DECLARE @eventID int
EXEC @eventID = zsystem.Events_TaskStarted '%s', %s, '%s', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, @parentID=%s
SELECT @eventID""" % (
            taskName,
            fixedTextSql,
            eventText.replace("'", "''"),
            SqlIntOrNULL(int_1),
            SqlIntOrNULL(int_2),
            SqlIntOrNULL(int_3),
            SqlIntOrNULL(int_4),
            SqlIntOrNULL(int_5),
            SqlIntOrNULL(int_6),
            SqlIntOrNULL(int_7),
            SqlIntOrNULL(int_8),
            SqlIntOrNULL(int_9),
            SqlDateOrNULL(date_1),
            SqlIntOrNULL(int_9),
            parentID or "NULL"
            )
    try:
        curr.execute(sql)
    except:
        print sql
        raise
    newEventID = curr.fetchone()[0]

    return newEventID

def LogTaskCompleted(eventID, eventText="", int_1=None, int_2=None, int_3=None, int_4=None, int_5=None, int_6=None, int_7=None, int_8=None, int_9=None, date_1=None, fixedText=None):
    curr = ConnectToMetricsDB()
    fixedTextSql = "NULL"
    if fixedText:
        fixedTextSql = "'%s'" % (fixedText or "").replace("'", "''")
    sql = """EXEC zsystem.Events_TaskCompleted %s, '%s', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NULL, NULL, %s""" % (
            eventID,
            eventText.replace("'", "''"),
            SqlIntOrNULL(int_1),
            SqlIntOrNULL(int_2),
            SqlIntOrNULL(int_3),
            SqlIntOrNULL(int_4),
            SqlIntOrNULL(int_5),
            SqlIntOrNULL(int_6),
            SqlIntOrNULL(int_7),
            SqlIntOrNULL(int_8),
            SqlIntOrNULL(int_9),
            SqlDateOrNULL(date_1),
            fixedTextSql,
            )
    try:
        curr.execute(sql)
    except:
        print sql
        raise

def LogTaskInfo(eventID, eventText="", int_1=None, int_2=None, int_3=None, int_4=None, int_5=None, int_6=None, int_7=None, int_8=None, int_9=None, date_1=None, fixedText=None):
    curr = ConnectToMetricsDB()
    fixedTextSql = "NULL"
    if fixedText:
        fixedTextSql = "'%s'" % (fixedText or "").replace("'", "''")
    sql = """EXEC zsystem.Events_TaskInfo %s, '%s', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NULL, NULL, %s""" % (
            eventID,
            eventText.replace("'", "''"),
            SqlIntOrNULL(int_1),
            SqlIntOrNULL(int_2),
            SqlIntOrNULL(int_3),
            SqlIntOrNULL(int_4),
            SqlIntOrNULL(int_5),
            SqlIntOrNULL(int_6),
            SqlIntOrNULL(int_7),
            SqlIntOrNULL(int_8),
            SqlIntOrNULL(int_9),
            SqlDateOrNULL(date_1),
            fixedTextSql,
            )
    try:
        curr.execute(sql)
    except:
        print sql
        raise

def LogTaskError(eventID, eventText="", int_1=None, int_2=None, int_3=None, int_4=None, int_5=None, int_6=None, int_7=None, int_8=None, int_9=None, date_1=None, fixedText=None):
    curr = ConnectToMetricsDB()
    fixedTextSql = "NULL"
    if fixedText:
        fixedTextSql = "'%s'" % (fixedText or "").replace("'", "''")
    sql = """EXEC zsystem.Events_TaskError %s, '%s', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NULL, NULL, %s""" % (
            eventID,
            eventText.replace("'", "''"),
            SqlIntOrNULL(int_1),
            SqlIntOrNULL(int_2),
            SqlIntOrNULL(int_3),
            SqlIntOrNULL(int_4),
            SqlIntOrNULL(int_5),
            SqlIntOrNULL(int_6),
            SqlIntOrNULL(int_7),
            SqlIntOrNULL(int_8),
            SqlIntOrNULL(int_9),
            SqlDateOrNULL(date_1),
            fixedTextSql,
            )
    try:
        curr.execute(sql)
    except:
        print sql
        raise

