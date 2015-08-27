# -*- coding: utf-8 -*-
# this file is released under public domain and you can use without limitations
import types, locale, datetime, collections, pyodbc
import time
from pprint import pprint
import sys

INFO_BY_STATUS = {
    -1 : {"background": "row_none", "icon": "monitor_notrun.png"}, # Pending
    0  : {"background": "row_none", "icon": "monitor_notrun.png"}, # Unknown
    1  : {"background": "row_progress", "icon": "monitor_running.png"}, # In progress
    2  : {"background": "row_good", "icon": "monitor_good.png"}, # Finished
    3  : {"background": "row_warning", "icon": "monitor_warning.png"}, # Warning
    4  : {"background": "row_bad", "icon": "monitor_bad.png"}, # Error
}
def index():
    if "index" not in request.url:
        redirect(request.url + "/index")
    return {}

def ProcessRows(rows):
    ret = {}
    for r in rows:
        d = {
            "statusDetail" : r.statusDetail,
            "statusID"     : r.statusID,
            "status"       : r.status,
            "duration"     : r.duration,
            "avgDuration"  : r.avgDuration,
            "percentComplete" : r.percentComplete,
            "startTime"    : r.startTime,
            "inOvertime"    : r.inOvertime,
            "percentComplete" : r.percentComplete,
        }
        info = INFO_BY_STATUS.get(d["statusID"], {})
        d = dict(d.items() + info.items())
        if r.percentComplete > 1.5 and r.statusID == 1:
            pct = " (overdue)"
            if int(r.duration.split(":")[0]) >= 1: 
                d["background"] = "row_danger"
                d["icon"] = "monitor_running_error.png"
        else:
            pct = " (%.0f%%)" % (100*r.percentComplete)
        d["percentCompleteString"] = pct
        ret[r.name] = d

    return ret

def JobStatus():
    sql = "SELECT * FROM ebs_FACTORY.monitor.jobExecutionStatus"
    rows = dbmetrics.executesql(sql)
    ret = ProcessRows(rows)
    return {"rows" : ret, "title": "Job Status"}

def SSISStatus():
    sql = "SELECT * FROM ebs_FACTORY.monitor.ssisExecutionStatus"
    rows = dbmetrics.executesql(sql)
    ret = ProcessRows(rows)
    return {"rows" : ret, "title": "SSIS Package Status"}

def TasksInProgress():
    factorySql = "EXEC ebs_FACTORY.factory.Events_InProgress"
    factoryRows = dbmetrics.executesql(factorySql)
    metricsSql = "EXEC ebs_METRICS.metric.Events_InProgress"
    metricsRows = dbmetrics.executesql(metricsSql)
    taskManagerSQL = "EXEC rdb_TASKMANAGER.task.Task_TasksInProgress"
    taskManagerRows = dbmetrics.executesql(taskManagerSQL)
    
    taskManagerIdleSQL = "EXEC rdb_TASKMANAGER.task.Task_IdleTasks"
    taskManagerIdleRows = dbmetrics.executesql(taskManagerIdleSQL)
    taskManagerFailedSQL = "EXEC rdb_TASKMANAGER.task.Task_FailedTasks"
    taskManagerFailedRows = dbmetrics.executesql(taskManagerFailedSQL)

    
    results = {
        "results": [("EVE_Metrics tasks in progress", metricsRows), 
                    ("Factory tasks in progress", factoryRows),
                    ("Task Manager tasks in progress", taskManagerRows)],
        "idleFailed": [("Task Manager idle tasks", taskManagerIdleRows),
                       ("Task Manager failed tasks", taskManagerFailedRows)]

    }




    return results

def TaskReport():
    rows = dbmetrics.executesql("EXEC metric.TaskReports_Select")
    report = request.vars.report or "nightly.process"
    dt = request.vars.dt
    if dt:
        dt = datetime.datetime.strptime(dt, "%Y-%m-%d")
    else:
        dt = datetime.datetime.today()
    if dt > datetime.datetime.now():
        session.flash = "Date is in the future, you silly billy"
        redirect(request.env.http_referer)
    dtString = dt.strftime("%Y-%m-%d")
    reports = collections.OrderedDict()
    for r in rows:
        reports[r.report] = r.title
    sql = "EXEC metric.TaskReports_Report '%s', '%s'" % (report, dtString)
    #sql = "EXEC metric.TaskReports_Report '%s'" % (report)
    rows = dbmetrics.executesql(sql)
    currDate = datetime.datetime.today()
    for r in rows:
        print r.startTime, type(r.startTime)

    return {
        "rows"      : rows,
        "currDate"  : currDate,
        "reports"   : reports,
        "report"    : report,
        "dt"        : dt,
        "dtString"  : dtString,
        }
