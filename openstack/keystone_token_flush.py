#!/usr/bin/env python
"""Print a set of mysql query to flush expired tokens.

  Splits the deletion in 30 minutes chunks to reduce lock duration on MariaDB.

  BEWARE: relies on the machine current timestamp to pick the right value for current_date.
"""
from datetime import datetime
from datetime import timedelta
from subprocess import check_output
import shlex


if __name__ == '__main__':
    interval = timedelta(minutes=30)
    back = timedelta(days=2)
    current_date = datetime.now()
    
    query_fmt = 'delete from keystone.token where token.expires between "{start_date}" and "{end_date}" and token.expires < "{current_date}";'
    date_fmt = '%Y-%m-%d %H:%M:00'
    
    start_date = current_date - back
    end_date = start_date + interval
    while end_date < current_date:
       print(query_fmt.format(
           start_date=start_date.strftime(date_fmt),
           end_date=end_date.strftime(date_fmt),
           current_date=current_date.strftime(date_fmt)
       ))
       start_date += interval
       end_date += interval
