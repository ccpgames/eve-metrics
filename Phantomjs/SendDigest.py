import smtplib, subprocess, uuid, os, sys, datetime, json, getopt, urllib2, traceback, locale
from collections import namedtuple

import digestutil
from PIL import Image

from email.MIMEMultipart import MIMEMultipart
from email.MIMEText import MIMEText
from email.MIMEImage import MIMEImage

SMTP_SERVER = "SMTP"
SAVE_IMG_PATH = "..\\web2py\\applications\\evemetrics\\static\\images\\digest\\"
SENDER = "EVE Metrics Digest <evemetricsdigest@ccpgames.com>"
ERROR_EMAIL_ADDRESS = "digesterror@ccpgames.com,digesterror@ccpgames.com"

BASE_URL = "http://evemetrics/"

#BASE_URL = "http://127.0.0.1/evemetrics/default/"

DEFAULT_ZOOM = 1.0
DEFAULT_WIDTH = 700
DEFAULT_HEIGHT = 400
DEFAULT_BKCOL = "#edb400"
DEFAULT_COL = "#000000"
DEFAULT_FONTSIZE = 18
ACCESS_SECRET = "GOODACC4SSSECRET4YOU" # secret passcode to override eve metrics access restrictions

AlertRet = namedtuple("AlertRet", ["counterID", "counterName", "subjectID", "subjectText", "keyID", "keyText", "value"])

import logging
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s", datefmt="%Y.%m.%d %H:%M:%S")

handler = logging.StreamHandler()
handler.setFormatter(formatter)
logger.addHandler(handler)

handler = logging.FileHandler("logs/digest_%s.log" % (datetime.datetime.now().strftime("%Y.%m.%d")), "a", encoding=None, delay="true")
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
logger.addHandler(handler)

def SectionDescription(desc):
    if not desc:
        return ""
    desc = desc.replace("\n", "<br>")
    ret = """
    <table width=\"100%%\" style=\"margin-bottom:5px;\">
    <tr><td style=\"font-size:12px;font-family: Verdana;color:#666666;padding:5px 0px 0px 5px;\">
      %s
    </td></tr></table>""" % desc
    return ret

def SectionHeader(row, url):
    bkCol = row.backgroundColor
    col = row.color or "#000000"
    icon = row.icon or ""
    fontSize = row.fontSize or DEFAULT_FONTSIZE
    iconPosition = row.iconPosition or "left"
    title = row.sectionTitle
    if bkCol:
        bkCol = "background-color:%(bkCol)s;" % {"bkCol" : bkCol}

    iconLeft = ""
    iconRight = ""
    if icon:
        if iconPosition == "left":
            iconLeft = "<td width=\"1%%\" style=\"padding:8px 0px 8px 8px;%(bkCol)s;height:20px;\"><img src=\"cid:%(icon)s\"></td>" % {"bkCol" : bkCol, "icon": icon}
        else:
            iconRight = "<td width=\"1%%\" style=\"padding:8px 8px 8px 0px;%(bkCol)s;height:20px;\"><img src=\"cid:%(icon)s\"></td>" % {"bkCol" : bkCol, "icon": icon}
    if url:
        titleWithUrl = digestutil.A("%s" % url, title, _style="color:%(col)s;" % {"col" : col})
    else:
        titleWithUrl = title
    return """
    <table style=\"width:100%%\" cellspacing=0>
        <tr>
            %(iconLeft)s
            <td style=\"padding:8px;color:%(col)s;height:20px;text-decoration:none;%(bkCol)s\">
                <div style=\"font-size:%(fontSize)spx;\">
                %(title)s
                </div>
            </td>
            %(iconRight)s
        </tr>
    </table>
    """ % { 
        "title"     : titleWithUrl, 
        "bkCol"     : bkCol,
        "col"       : col,
        "iconRight" : iconRight,
        "iconLeft"  : iconLeft,
        "path"      : url,
        "fontSize"  : fontSize,

        }

def AlertHeader(counterID, counterName, cond, bkCol, col, icon, fontSize):
    if not bkCol:
        bkCol = DEFAULT_BKCOL
    if not col:
        col = DEFAULT_COL
    if icon:
        icon = "<td width=\"1%%\" style=\"padding:8px 0px 8px 8px;background-color:%s;height:20px;\"><img src=\"cid:%s\"></td>" % (bkCol, icon)
    else:
        icon = ""
    if not fontSize:
        fontSize = DEFAULT_FONTSIZE

    return """
    <table style=\"width:100%%\" cellspacing=0>
        <tr>
            %(icon)s
            <td style=\"padding:8px;background-color:%(bkCol)s;color:%(col)s;height:20px;\">
                <div style=\"font-size:%(fontSize)spx;\">%(title)s</div>
            </td>
            <td style=\"padding:8px;background-color:%(bkCol)s;color:%(col)s;height:20px;font-size:12px;\" align=right>
                <div>%(cond)s</div>
            </td>
        </tr>
    </table>
    """ % { 
        "title"  : digestutil.A("Report?counterID=%s" % counterID, counterName, _style="color:%(col)s;" % {"col" : col}), 
        "cond"   : cond,
        "bkCol"  : bkCol,
        "col"    : col,
        "icon"   : icon,
        "fontSize" : fontSize,
        }

def SendDigest(digestID, emailSubject, emailAddresses, emailAddressesCC, header, digestSections, images, alert=0):
    #emailSubject += " %s" % (datetime.datetime.now() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")
    emailBody = "%s" % header
    for s in digestSections:
        emailBody += s
    emailBody += "<br><div style=\"font-size:11px;color:#666666;border-top:1px solid #CCCCCC;\">This email was sent by the EVE Metrics Digest System.<br>%s.</div>" % digestutil.A("ViewDigest?digestID=%s" % digestID, "Click here to manage your digest subscription", _style="font-size:11px;color:#666666;")
    body = "<html><body style=\"font-family: Verdana;\"><style>td {margin:0px; font-family: Verdana;padding:3px;font-size:13px;}</style>%s</body></html>" % emailBody

    msgRoot = MIMEMultipart('related')
    if alert == 3:
        msgRoot['X-Priority'] = '2'
        emailSubject = "[Alert] " + emailSubject
    elif alert == 2:
        emailSubject = "[Warning] " + emailSubject
    msgRoot['Subject'] = emailSubject
    msgRoot['From'] = SENDER
    msgRoot['To'] = ";".join(emailAddresses)
    msgRoot['CC'] = ";".join(emailAddressesCC)
    msgRoot.preamble = 'This is a multi-part message in MIME format.'
    
    msgAlternative = MIMEMultipart('alternative')
    msgRoot.attach(msgAlternative)
    body = body.encode("UTF-8", errors="ignore")
    msgText = MIMEText(body, 'html')
    msgAlternative.attach(msgText)
    for img in images:
        fp = open(os.path.join(SAVE_IMG_PATH, img), 'rb')
        msgImage = MIMEImage(fp.read())
        fp.close()
        msgImage.add_header('Content-ID', '<%s>' % os.path.split(img)[-1])
        msgRoot.attach(msgImage)

    smtp = smtplib.SMTP()
    smtp.connect(SMTP_SERVER)
    emails = emailAddresses + emailAddressesCC
    smtp.sendmail("evemetricsdigest@ccpgames.com", emails, msgRoot.as_string())
    smtp.quit()

def AlertEntry(txt, counterID, subjectID, keyID, formattedValue):
    link = digestutil.A("Counters?graph=%s_%s_%s" % (counterID, subjectID, keyID), txt)
    ret = "<tr><td style=\"font-size:14px;\">%s</td><td style=\"font-size:14px;text-align:right;\"><nobr>%s</nobr></td></tr>" % (link, formattedValue)
    return ret

def CheckAlert(curr, alertRow):
    config = json.loads(alertRow.config)
    method = alertRow.method
    severity = 0
    if method == "VALUE":
        ret = CheckAlert_Value(curr, alertRow.counterID, alertRow.subjectID, alertRow.keyID, config["dir"], int(config["value"]))
    elif method == "PERCENT":
        ret = CheckAlert_Percent(curr, alertRow.counterID, alertRow.subjectID, alertRow.keyID, float(config["value"]), int(config["minValue"]), int(config["days"]))
    else:
        raise Exception("Unsupported alert method! %s" % method)
    txt = None
    if ret:
        condString = ret["condition"]
        rows       = ret["rows"]
        severity   = alertRow.severity
        title      = alertRow.alertTitle or rows[0].counterName
        if severity == 3:
            title      = "ALERT: %s" % title
        elif severity == 2:
            title      = "Warning: %s" % title

        txt = AlertHeader(alertRow.counterID, title, condString, alertRow.backgroundColor , alertRow.color, alertRow.icon, alertRow.fontSize)
        txt += "<table width=\"100%%\">"
        for r in rows:
            logging.info("Alert triggered: %s" % repr(r))
            if r.subjectText:
                alertTxt = r.subjectText
                if r.keyText:
                    alertTxt = "<b>%s</b> - %s" % (r.subjectText, r.keyText)
            else:
                alertTxt = "%s" % (r.keyText)
            txt += AlertEntry(alertTxt, r.counterID, r.subjectID, r.keyID, r.value)
        txt += "</table>"
        txt += SectionDescription(alertRow.description)
        txt += "<br>&nbsp;"
    return txt, severity

def CheckAlert_Value(curr, counterID, subjectID, keyID, cond, value):
    sql = """
EXEC metric.Alerts_CheckValue %(counterID)s, NULL, %(subjectID)s, %(keyID)s, '%(condition)s', %(value)s
    """ % {"counterID": counterID, "subjectID": subjectID if subjectID is not None else "NULL", "keyID": keyID or "NULL", "condition": cond, "value": value}
    logging.debug(sql)
    curr.execute(sql)
    rows = curr.fetchall()
    if not rows:
        return None

    ret = {
        "condition" : "%s %s" % ({"U": "<", "O": ">"}[cond], digestutil.FmtAmtSmart(value)),
        "rows" : [],
    }
    for r in rows:
        logging.info("Value Alert triggered: %s" % r)
        ret["rows"].append(AlertRet(counterID=r.counterID, counterName=r.counterName, subjectID=r.subjectID, subjectText=r.subjectText, keyID=r.keyID, keyText=r.keyText, value="<b>%s</b>" % digestutil.FmtAmtSmart(r.value)))
    return ret

def CheckAlert_Percent(curr, counterID, subjectID, keyID, value, minValue, days):
    sql = """
EXEC metric.Alerts_CheckPercent %(counterID)s, NULL, %(subjectID)s, %(keyID)s, %(value)s, %(minValue)s, %(days)s
    """ % {"counterID": counterID, "subjectID": subjectID if subjectID is not None else "NULL", "keyID": keyID or "NULL", "value": value, "minValue": minValue, "days": days}
    logging.debug(sql)
    curr.execute(sql)
    rows = curr.fetchall()
    if not rows:
        return None

    ret = {
        "condition" : ">%.0f%% increase between %s days ago and yesterday" % (value, days),
        "rows" : [],
    }
    for r in rows:
        logging.info("Percent Alert triggered: %s" % r)
        ret["rows"].append(AlertRet(counterID=r.counterID, counterName=r.counterName, subjectID=r.subjectID, subjectText=r.subjectText, keyID=r.keyID, keyText=r.keyText, value="<b>%s</b> (+%.0f%%)" % (digestutil.FmtAmtSmart(r.value), (r.pctDiff-1.0)*100.0)))
    return ret

def GenerateDigest(curr, digestRow, emailAddresses=None, parentEventID=None):
    eventID = digestutil.LogTaskStarted("Digest", fixedText=digestRow.emailSubject, parentID=parentEventID)
    try:
        digestID = digestRow.digestID
        emailAddressesCC = []
        if not emailAddresses:
            emailAddresses = []
            sql = "SELECT emailAddress, cc FROM metric.digestEmails WHERE digestID = %d ORDER BY mailingList ASC, emailAddress ASC" % digestID
            curr.execute(sql)
            rows = curr.fetchall()
            for r in rows:
                if not r.cc:
                    emailAddresses.append(r.emailAddress)
                else:
                    emailAddressesCC.append(r.emailAddress)
        else:
            emailAddresses = emailAddresses.split(",")
        digestSections = []
        images = set()
        header = ""
        alertSeverity = 0
        if digestRow.description and digestRow.sendDescription:
            header = "<div style=\"font-size:12px;font-family: Verdana;color:#666666;\">%s<div><br>" % digestRow.description.replace("\n", "<br>")

        sql = "SELECT * FROM metric.digestAlerts a LEFT JOIN metric.digestSectionTemplates t ON t.templateID = a.templateID WHERE a.digestID = %(digestID)s ORDER BY a.position, a.alertID" % {"digestID": digestID}
        curr.execute(sql)
        rows = curr.fetchall()
        numAlerts = len(rows)
        numTriggeredAlerts = 0
        if rows:
            logging.info("Found %s alerts for digest %s", len(rows), digestID)
            for i, r in enumerate(rows):
                logging.info("Checking alert %s/%s" % (i, len(rows)))
                thisSeverity = 0
                try:
                    alertText, thisSeverity = CheckAlert(curr, r)
                except Exception as e:
                    alertText = "Exception occurred checking alert %s: %s<br><br>" % (r.alertID, traceback.format_exc())
                    logging.error(alertText)
                    digestutil.LogTaskError(eventID, alertText)
                    #raise #!!!

                if alertText:
                    numTriggeredAlerts += 1
                    digestSections.append(alertText)
                    if r.icon:
                        images.add("../templates/" + r.icon)
                alertSeverity = max(thisSeverity, alertSeverity)

        sql = "SELECT * FROM metric.digestSections s LEFT JOIN metric.digestSectionTemplates t ON t.templateID = s.templateID WHERE s.digestID = %(digestID)s ORDER BY s.position, s.sectionID" % {"digestID": digestID}
        curr.execute(sql)
        rows = curr.fetchall()

        if not rows and not digestSections:
            logging.warning("Digest %s has no sections. I will not send this nonsense!" % digestID)
            digestutil.LogTaskCompleted(eventID, "This digest is empty")
            return False
        if not alertSeverity and digestRow.onlyAlert:
            logging.info("There are no alerts in digest %s and I am told only to send it when there is an alert. Aborting." % digestID)
            digestutil.LogTaskCompleted(eventID, "No triggered alerts")
            return False

        for r in rows:
            logging.debug("... %s" % r)
            contentConfig = {}
            if r.contentConfig:
                contentConfig = json.loads(r.contentConfig)
            if r.icon:
                images.add("../templates/" + r.icon)
            if isinstance(contentConfig, dict):
                contentConfig2 = []
                for k, v in contentConfig.iteritems():
                    contentConfig2.append([k, v])
                contentConfig = contentConfig2
            urlToSnap = ""
            urlToClick = ""
            zoom = r.zoom or DEFAULT_ZOOM
            sectionTitle = r.sectionTitle
            width = r.width or DEFAULT_WIDTH
            height = r.height or DEFAULT_HEIGHT
            if r.contentType == "GRAPH":
                urlToSnap = "EmbeddedCounters?"
                for cfg in contentConfig:
                    urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
                #urlToSnap += "w=640"
                urlToClick = urlToSnap.replace("Embedded", "")
                urlToSnap += "w=%s&h=%s&" % (width, height)
            elif r.contentType == "DASHBOARD":
                urlToSnap = "EmbeddedDashboard?"
                for cfg in contentConfig:
                    urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
                urlToClick = urlToSnap.replace("Embedded", "")
                urlToSnap += "embedded=1&nomargin=1&hidetitle=1&"
            elif r.contentType == "DASHBOARDGRAPHS":
                urlToSnap = "EmbeddedDashboardGraphs?"
                for cfg in contentConfig:
                    urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
                urlToClick = urlToSnap.replace("Embedded", "")
                urlToSnap += "w=%s&h=%s&" % (width, height)
            elif r.contentType == "REPORT":
                urlToSnap = "EmbeddedReport?"
                urlToClick = "Report?"
                for cfg in contentConfig:
                    urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
                    if cfg[0] not in ("maxRows", ): # exclude some stuff megahack
                        urlToClick += "%s=%s&" % (cfg[0], cfg[1])
                logging.info("urlToClick = %s", urlToClick)
                urlToSnap += "hidetitle=1&hideids=1&"
            elif r.contentType == "NUMBER":
                urlToSnap = "FetchCount?"
                for cfg in contentConfig:
                    urlToSnap += "%s=%s&" % (cfg[0], cfg[1])
                urlToClick = urlToSnap.replace("FetchCount", "Report")
                urlToSnap += "style=font-family:Verdana font-size:24px color:green&"
                width = 200
            elif r.contentType == "HEADER":
                urlToSnap = ""
                urlToClick = ""
            else:
                txt = "Unknown contentType %s" % r.contentType
                logging.error(txt)
                digestutil.LogTaskError(eventID, txt)
                continue

            title = SectionHeader(r, urlToClick)
            description = SectionDescription(r.description)
            if urlToSnap:
                urlToSnap += "secret=%s" % ACCESS_SECRET
                logging.info("I will snap %s" % urlToSnap)
                imgName = str(uuid.uuid1()) + ".png"
                images.add(imgName)
                img = "%s%s" % (SAVE_IMG_PATH, imgName)
                lst = ["phantomjs.exe", "rasterize_evemetricsdigest.js", "%(base)s%(path)s" % {"base" : BASE_URL, "path" : urlToSnap}, img, "%s"% (width), "%s" % zoom]
                logging.debug("Opening %s" % (" ".join(lst)))
                p = subprocess.Popen(lst, stdout=subprocess.PIPE, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
                stdout, stderr = p.communicate()
                logging.debug("%s, %s", stdout, stderr)

                imageHandle = Image.open(img)
                outputWidth, outputHeight = imageHandle.size

                if outputHeight > digestutil.MAX_IMAGE_HEIGHT:
                    imageSplits = digestutil.SplitImage(imgName)
                    logging.warning("Image for section %s is too tall so I have split it into %s parts\n" % (sectionTitle, len(imageSplits)))
                    for i in imageSplits:
                        images.add(i)
                    imagesText = ""
                    for img in imageSplits:
                        imagesText += "<img src=\"cid:%(img)s\"><br>" % {
                            "img"     : img,
                        }
                    logging.info(imagesText)

                    digestSections.append("%(title)s%(description)s<a href=\"%(base)s%(path)s\">%(imgs)s</a><br>&nbsp;" % {
                        "title"         : title, 
                        "base"          : BASE_URL, 
                        "path"          : urlToClick, 
                        "imgs"          : imagesText, 
                        "description"   : description, 
                        })


                else:
                    digestSections.append("%(title)s%(description)s<a href=\"%(base)s%(path)s\"><img src=\"cid:%(img)s\" height=\"%(height)s\" width=\"%(width)s\" style=\"height:%(height)spx; width:%(width)spx; \"></a><br>&nbsp;" % {
                        "title"         : title, 
                        "base"          : BASE_URL, 
                        "path"          : urlToClick, 
                        "img"           : imgName, 
                        "description"   : description, 
                        "height"        : outputHeight,
                        "width"         : outputWidth,
                        })
            else:
                logging.info("No URL to snap. Just adding section %s" % r.sectionTitle)
                digestSections.append("%(title)s%(description)s<br>" % {
                    "title"         : title, 
                    "description"   : description, 
                    })

        txt = "Sending out digest with ID %s titled %s containing %s sections to %s (cc: %s)" % (digestID, digestRow.emailSubject, len(digestSections), ",".join(emailAddresses), ",".join(emailAddressesCC))
        logging.info(txt)
        SendDigest(digestRow.digestID, digestRow.emailSubject, emailAddresses, emailAddressesCC, header, digestSections, images, alertSeverity)

        digestutil.LogTaskCompleted(eventID, txt, int_1=numAlerts, int_2=numTriggeredAlerts)
        return True
    except:
        txt = "Fatal error generating digest #%s:\n%s" % (digestRow.digestID, traceback.format_exc())
        digestutil.LogTaskError(eventID, txt)
        logging.error(txt)

def main(digestID=None, email=None):
    if digestID:
        logging.info("Generating specific digest %s for emails %s" % (digestID, email or ("[default]")))
    else:
        logging.info("Generating digests")
    curr = digestutil.MakeCursor()
    if digestID:
        sql = "SELECT * FROM metric.digests WHERE digestID = %d" % digestID
        eventText = "Generating a single digest for emails: %s" % email or ("[default]")
    else:
        sql = """
SELECT * 
  FROM metric.digests 
 WHERE disabled <> 1 AND 
       (scheduleType = 'DAY' OR 
       (scheduleType = 'WEEK' AND DATEPART(dw, GETUTCDATE()) = scheduleDay) OR
       (scheduleType = 'MONTH' AND DATEPART(d, GETUTCDATE()) = scheduleDay)
       )
 ORDER BY digestID ASC
        """
    curr.execute(sql)
    rows = curr.fetchall()
    eventText = "Generating a total of %s digests" % len(rows)
    if email:
        eventText += " for email: %s" % email
    eventID = digestutil.LogTaskStarted("DigestBatch", eventText, int_1=len(rows), fixedText="single digest" if digestID else "ALL DIGESTS")
    numSent = 0
    numFailed = 0
    for r in rows:
        logging.info("Generating digest %s (%s: %s)..." % (r.digestID, r.scheduleType, r.scheduleDay))
        logging.debug(r)
        try:
            ret = GenerateDigest(curr, r, emailAddresses=email, parentEventID=eventID)
            if ret: numSent += 1
        except:
            numFailed += 1
    digestutil.LogTaskCompleted(eventID, "Done sending out %s/%s digests" % (len(rows), numSent), int_1=len(rows), int_2=numSent, int_3=numFailed)
    logging.info("Done sending out %s digests" % len(rows))

if __name__ == "__main__":
    try:

        digestID = None
        email = None
        opts, args = getopt.getopt(sys.argv[1:], "d:e:", ["digest=", "email="])
        for opt, arg in opts:
            if opt in ("-d", "--digest"):
                digestID = int(arg)
            elif opt in ("-e", "--email"):
                email = arg
        if not digestID: # full digest
            error = digestutil.GetEveMetricsError()
            if error:
                logging.critical(error)
                digestutil.SendEmail(ERROR_EMAIL_ADDRESS, "Error sending Digest", "There was a problem getting latest information from Eve Metrics: %s" % error)
                eventID = digestutil.LogTaskStarted("DigestBatch", "Starting to send digests...", fixedText="ALL")
                digestutil.LogTaskError(eventID, error)
                digestutil.LogTaskCompleted(eventID, "Unable to send digests due to error.", fixedText="ALL")
                sys.exit(1)

        main(digestID, email)
    except Exception as e:
        logging.critical(traceback.format_exc())
