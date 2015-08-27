#!/usr/bin/python
# -*- coding: utf-8 -*-

# when web2py is run as a windows service (web2py.exe -W)
# it does not load the command line options but it
# expects to find conifguration settings in a file called
#
#   web2py/options.py
#
# this file is an example for options.py

import socket
import os

ip = '127.0.0.1'
port = 443
interfaces=[('127.0.0.1', 443)]
password = 'a'  # ## <recycle> means use the previous password
pid_filename = 'httpserver_evemetrics_https.pid'
log_filename = 'httpserver_evemetrics_https.log'
profiler_filename = None
ssl_certificate = 'evemetrics.crt'  # ## path to certificate file
ssl_private_key = 'evemetrics.key'  # ## path to private key file
numthreads = 50 # ## deprecated; remove
minthreads = None
maxthreads = None
server_name = socket.gethostname()
request_queue_size = 5
timeout = 30
shutdown_timeout = 5
folder = os.getcwd()
extcron = None
nocron = None

# CCP extensions
service_name = "web2py_evemetrics_https"
service_display_name = "Eve Metrics Website HTTPS"