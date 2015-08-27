
routes_in = (
    # PRODUCTION RULES
    (".*:(http|https)://evemetrics:(get|post) /admin/(?P<any>[\w\./_-]+)", "/admin/\g<any>"),
    (".*:(http|https)://evemetrics:(get|post) /static/(?P<any>[\w\./_-]+)", "/evemetrics/static/\g<any>"),
    (".*:(http|https)://evemetrics:(get|post) (?P<any>.*)", "/evemetrics/default\g<any>"),
)


routes_out = (
    # localhost rules for development
    # example urls:
    # http://127.0.0.1/evemetrics/default/Report?counterID=1
    (".*:(http|https)://127.0.0.1:(get|post) (?P<any>.*)/default/static/(?P<file>[\w\./_-]+)", "\g<any>/static/\g<file>"),
    (".*:(http|https)://127.0.0.1:(get|post) (?P<any>.*)/servicemonitor/static/(?P<file>[\w\./_-]+)", "\g<any>/static/\g<file>"),
    (".*:(http|https)://127.0.0.1:(get|post) (?P<any>.*)/default/(?P<file>[\w\./_-]+)", "\g<any>/default/\g<file>"),
    (".*:(http|https)://127.0.0.1:(get|post) (?P<any>.*)/servicemonitor/(?P<file>[\w\./_-]+)", "\g<any>/servicemonitor/\g<file>"),

    # PRODUCTION RULES 
    # example urls:
    # http://evemetrics/Report?counterID=1

    (".*:(http|https)://evemetrics:(get|post) /evemetrics/default/index", "/"),
    (".*:(http|https)://evemetrics:(get|post) /evemetrics/default/(?P<file>[\w\./_-]+)", "/\g<file>"),
    (".*:(http|https)://evemetrics:(get|post) /evemetrics/static/(?P<file>[\w\./_-]+)", "/static/\g<file>"),
)
