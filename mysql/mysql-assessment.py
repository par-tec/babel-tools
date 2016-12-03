#!/usr/bin/python3
"""
Utilities for mangling redmine entries.
"""
from __future__ import print_function, unicode_literals
__author__ = 'rpolli'
import logging
import getpass
import os
import datetime
import shlex
import string
from itertools import product
try:
    from urllib.parse import urlparse
except:
    from urlparse import urlparse

import mysql.connector
try:
    import pyoo
except ImportError:
    raise SystemExit("Missing rpm|apt package: libreoffice-pyuno")

log = logging.getLogger()
logging.basicConfig(level=logging.INFO)

# Ugly kludge to easy sheet positions.
for k, v in zip(string.ascii_uppercase, range(30)):
    globals()[k] = v


def get_entries(uri='mysql://root:root@mysql'):
    """Get current status
    """
    connectstring = urlparse(uri)
    password = connectstring.password or getpass.getpass(
        "Insert password for %s" % connectstring.username)

    cnx = mysql.connector.connect(user=connectstring.username,
                                  password=password,
                                  host=connectstring.hostname,
                                  port=connectstring.port or 3306
                                  )
    cur = cnx.cursor()

    cur.execute("show global status;")
    ret = {k.lower(): v for k, v in cur.fetchall()}

    cur.execute("show variables;")
    ret.update({k.lower(): v for k, v in cur.fetchall()})

    cur.execute("show engine performance_schema status;")
    ret.update({k.lower(): v for _, k, v in cur.fetchall()
                if k.lower() == 'performance_schema.memory'})

    cur.close()
    cnx.close()
    return ret

def parse_status(fpath):
    with open(fpath) as fh:
        clean_lines = (line.replace("|", "").strip() for line in fh)
        split_lines = (line.split(" ", 1) for line in clean_lines if " " in line)
        strip_lines = (map(str.strip, row) for row in split_lines)
        parse_int = ((k,int(v) if v.isdigit() else v) for k,v in strip_lines)
        return {k.lower(): v for k, v in parse_int}
    

def get_oodesktop():
    from subprocess import Popen
    import atexit
    from time import sleep
    # Run and wait for the socket to be ready.
    ooserver = Popen(shlex.split(
        'soffice --accept="pipe,name=soffice.pipe;urp;" --norestore --nologo --nodefault --headless'))
    atexit.register(ooserver.terminate)
    sleep(5)
    log.info("Connecting to ooserver")
    desktop = pyoo.Desktop(pipe='soffice.pipe')
    return desktop


def expenses_xls(mysql_status, fpath="out.ods"):

    desktop = get_oodesktop()
    doc = desktop.open_spreadsheet('mysql_innodb_resource_requirements.ods')
    log.info("Spreadsheet open")
    sheet = doc.sheets[0]

    # Set basic info.
    sheet[0, D].value = mysql_status['version']

    # Netfish variables in the sheet.
    for row, column in product(range(80), range(80)):
        try:
            k = sheet[row, column].value.lower()
            if " " in k:
                k, comment = k.split(" ", 1)  # Allow comments in sheet.
            if k in mysql_status:
                log.info("Processing key %r", k)
                try:
                    sheet[row, column + 1].value = float(mysql_status[k])
                except (ValueError,) as e:
                    log.warning("Can't parse value %r: %r using unparsed data", k, mysql_status[k])
                    sheet[row, column + 1].value = str(mysql_status[k])
            
        except AttributeError:
            # cell value is not a label, skip.
            pass

    log.info("saving new document %r", fpath)
    doc.save(fpath)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(
        description='Get info from MySQL and populate an assessment sheet.')
    parser.add_argument(
        '--spent_on', type=str, default=datetime.datetime.now().strftime("%Y-%m-01"),
        help='Valid values: expenses, extra_time')
    parser.add_argument('--source', type=str, required=True,
                        help='Info source like a connect-string - eg: mysql://[root:secret@]mysql[:3306] - or a filename containing the output of SHOW VARIABLES; and SHOW GLOBAL STATUS')

    parser.add_argument('--out', type=str, required=True,
                        help='outfile')
    parser.add_argument('--debug', default=False,
                        action='store_true',
                        help='Dump server response in /tmp/dump.json.')
    args = parser.parse_args()

    # Get entries from redmine.
    print(args.source)
    
    if os.path.isfile(args.source):
        mysql_status = parse_status(args.source)
    else:
        mysql_status = get_entries(args.source)

    if args.debug:
        log.setLevel(logging.DEBUG)
        print(mysql_status)
        # simplejson.dump(mysql_status, open("/tmp/dump.json", "wb"))

    # Run the actual function.
    expenses_xls(mysql_status, args.out)


def test_get_status():
    entries = get_entries()
    assert entries
    assert [x for x in entries if 'ssl' in x.lower()]


def test_parse_status():
    ret = parse_status("test-status.out")
    assert "max_connections" in ret

def test_modify_sheet():
    entries = {
        'Ssl_session_cache_mode': 'Test placeholder',
        'max_connections': 1500,
        'innodb_buffer_pool_size': 2e+34,
        'innodb_open_files': 434,
        'query_cache_size': 123000,
        'version': 'Sample Version',
        'bytes_sent': 45,
        'max_heap_table_size': 44,
        'threads_connected': 124,
    }
    fpath = "test_modify_sheet.ods"
    expenses_xls(entries, fpath)
    assert os.path.isfile(fpath)
