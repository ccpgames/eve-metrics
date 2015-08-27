# -*- coding: utf-8 -*-
# this file is released under public domain and you can use without limitations

#########################################################################
## Customize your APP title, subtitle and menus here
#########################################################################

response.title = ' '.join(word.capitalize() for word in request.application.split('_'))
response.subtitle = ""#T('Graphs for the masses')

## read more at http://dev.w3.org/html5/markup/meta.name.html
response.meta.author = 'Team Zorglub <teamzorglub@ccpgames.com>'
response.meta.description = 'Eve Metrics'
response.meta.keywords = 'Eve, Metrics, CCP, Dust'
response.meta.copyright = 'Copyright CCP 2011-2015'

## your http://google.com/analytics id
response.google_analytics_id = None

#########################################################################
## this is the main application menu add/remove items as required
#########################################################################

response.menu = [
    (T('Home'), False, URL('default','index'), []),
    (T('Groups'), False, URL('default','Groups'), ["Groups"]),
    (T('Reports'), False, URL('default','Reports'), ["Report", "Counters"]),
    (T('Collections'), False, URL('default','Collections'), ["EditCollection"]),
    (T('Dashboards'), False, URL('default','Dashboards'), ["Dashboard"]),
    (T('Events'), False, URL('default','Markers'), ["ViewMarker", "AddMarker"]),
    (T('Digests'), False, URL('default','Digests'), []),
    (T('Tags'), False, URL('default','Tags'), []),
    (T('Admin'), False, URL('default','Admin'), ["ManageGroups", "ManageCollections", "ManageCounters", "EditCounter", "ViewLookupTables", "EditLookupTable"]),
    ]
