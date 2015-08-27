import sys, os, pyodbc, urllib, datetime, traceback, time, smtplib
import win32serviceutil
from pprint import pprint

RECIPIENT_EMAIL_ADDRESSES = ["evemetricswatchdog@ccpgames.com"]

SMTP_SERVER               = "smtp.ccpgames.com"
SENDER_EMAIL_ADDRESS      = "doobjob@ccpgames.com"

PID_FILE = ".WATCHDOG"

def FmtTime(dt):
    return dt.strftime("%Y-%m-%d %H:%M")

def SendEmail(title, body):
    sender = SENDER_EMAIL_ADDRESS
    receivers = RECIPIENT_EMAIL_ADDRESSES
    message = """From: Eve Metrics <%(fromemail)s>
To: %(email)s
MIME-Version: 1.0
Content-type: text
Subject: %(title)s

%(body)s
""" % {"fromemail": sender, "body": body, "email": str(receivers[0]), "title": title}
    try:
        smtpObj = smtplib.SMTP(SMTP_SERVER)
        smtpObj.set_debuglevel(True)
        smtpObj.sendmail(sender, receivers, message)         
        print "  Successfully sent email to %s" % receivers[0]
    except Exception, e:
        print "Error: unable to send email to %s: %s" % (receivers[0], e)
        raise

def TestWebsite(url):
    sys.stdout.write("TestWebsite %s... " % url)
    t = time.time()
    ret = ""
    url = "http://%s/Test" % url
    try:
        data = urllib.urlopen(url).read()
        if data != "OK":
            ret = "Error talking to website at %s. Response was %s" % (url, data[:128])
        else:
            diff = time.time()-t
            if diff > 60.0:
                ret = "It took %.1f seconds to get a response from %s" % (diff, url)
    except:
        ret = "Unable to reach website at %s" % url
    if ret:
        print "\n%s" % ret
    else:
        sys.stdout.write("OK!  ")
    return ret

def RestartService(svc, retry=0):
    print "Restarting service %s..." % svc
    try:
        win32serviceutil.RestartService(svc)
    except:
        print "Exception trying to restart service: %s" % traceback.format_exc()
        if not retry:
            print "Retrying..."
            RestartService(svc, 1)
        else:
            raise
    print "Done restarting service"

def main():
    try:
        f = open(PID_FILE, "rb")
        oldPid = int(f.read())
        print "Found old Pid, WTF???", oldPid
        # restart both services
        err = "I have restarted the web servers."
        try:
            RestartService("web2py_evemetrics")
        except Exception as e:
            err = "I encountered an exception trying to restart the services:\n\n%s" % traceback.format_exc()
        body = "Error report\n\nPrevious watchdog run has not completed! This might mean that a website is locked up!\n\n%s" % err
        SendEmail("Evelogs watchdog reports a problem!", body)
        f.close()
        time.sleep(2.0)
        try:
            os.remove(PID_FILE)
        except:
            pass
        return
    except IOError:
        pass

    f = open(PID_FILE, "w")
    f.write(repr(os.getpid()))
    f.close()
    try:
        results = []
        for url in ("evemetrics", ):
            try:
                result = TestWebsite(url)
                if result: results.append("TestWebsite - %s\n%s" % (url, result))
            except Exception as e:
                results.append("Exception running TestWebsite - %s:\n%s" % (url, traceback.format_exc()))

        if results:
            print "Results:"
            pprint(results)

            body = "Error report\n\n%s" % "\n\n".join(results)
            SendEmail("Evelogs watchdog reports a problem!", body)

    finally:
        try:
            os.remove(PID_FILE)
        except:
            pass

while 1:
    startTime = time.time()
    try:
        print datetime.datetime.now()
        main()
        print
    except:
        print "Exception: ", traceback.format_exc()
    finally:
        diff = time.time()-startTime
        if diff > 10:
            print "TIME WARNING!!! Done in %.2f seconds" % (diff)
        else:
            print "Done in %.2f seconds" % (diff)
        sys.exit(0)
        time.sleep(60)
