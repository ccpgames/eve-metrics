import win32serviceutil

def RestartService(name):
    try:
        ret = win32serviceutil.RestartService(name)
        print "Successfully restarted service %s. Return value was %s" % (name, ret)
    except Exception, e:
        print "Unable to restart service %s: %s" % (name, e)

RestartService("web2py_evemetrics")
RestartService("web2py_evelogs")
RestartService("web2py")
