#!/usr/bin/env python3
"""Writes a synthetic Stillbreak state file for README screenshots.

    python3 make-demo-state.py normal|overtime OUT.json
    open -n --env STILLBREAK_STATE_FILE=OUT.json \
         --env STILLBREAK_DISABLE_LOGIN_ITEM_MUTATION=1 .build/Stillbreak.app

"normal" starts a 6-minute-old interval (countdown about 19:00); "overtime" a
27-minute-old one (countdown below zero). History is about a week of invented
weekday intervals, so no real data ever reaches a screenshot. The override
variable keeps the app away from ~/Library/Application Support/Stillbreak.
"""
import json, uuid, random, sys, time, datetime as dt
random.seed(510)
mode = sys.argv[1]  # normal | overtime
out = sys.argv[2]
now = dt.datetime.now().astimezone()
def iso(d): return d.astimezone(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3]+'Z'
def seg(s,e,ot=False): return {"start":iso(s),"end":iso(e),"isOvertime":ot}
M = dt.timedelta(minutes=1)
history=[]
def day_intervals(day, starts):
    for (h,m,work,over,brk) in starts:
        s = day.replace(hour=h,minute=m,second=0,microsecond=0)
        if s >= now - 40*M: continue
        regular = work-over
        e = s+work*M
        segs=[seg(s,s+regular*M)]
        if over: segs.append(seg(s+regular*M,e,True))
        bs = e; be = e+brk*M
        history.append({"id":str(uuid.uuid4()).upper(),"intervalStart":iso(s),"intervalEnd":iso(e),
          "activeDuration":work*60,"overtimeDuration":over*60,"breakStart":iso(bs),"breakEnd":iso(be),
          "breakDuration":brk*60,"workSegments":segs})
plans = [
 [(9,0,25,0,6),(9,40,25,4,8),(10,30,22,0,12),(13,5,25,9,7),(14,0,25,0,15),(15,10,25,3,5),(16,0,18,0,30)],
 [(8,50,25,0,5),(9,35,25,0,9),(10,30,25,6,6),(11,25,20,0,45),(13,0,25,0,5),(13,45,25,12,8),(15,0,25,0,6),(15,45,25,2,10)],
 [(9,15,25,0,5),(10,0,25,8,10),(11,0,25,0,5),(11,45,15,0,50),(13,30,25,5,5),(14,20,25,0,7),(15,15,25,0,5),(16,5,25,15,10)],
 [(8,40,25,0,5),(9,25,25,0,10),(10,25,25,5,7),(11,20,25,0,60),(13,10,25,0,5),(14,0,25,10,6),(15,0,25,0,9)],
 [(9,5,25,0,6),(9,50,25,3,5),(10,40,25,0,10),(11,40,25,7,55),(14,0,25,0,5),(14,45,25,0,8),(15,35,12,0,20)],
 [],[],
]
today = now.replace(hour=0,minute=0,second=0,microsecond=0)
# weekdays only: iterate past 7 days
for back in range(1,8):
    d = today - dt.timedelta(days=back)
    if d.weekday()>=5: continue
    day_intervals(d, plans[back%5])
day_intervals(today, [(7,25,25,0,6),(8,2,17,0,3)])
history.sort(key=lambda r:r["intervalStart"])
settings={"workThreshold":1500,"deadTime":300,"notificationsEnabled":True,"soundEnabled":True,"launchAtLogin":True}
if mode=="normal": mins=6; over=0
else: mins=27; over=2
s = now - mins*M
segs=[seg(s,s+25*M)]
if over: segs.append(seg(s+25*M,now,True))
else: segs=[seg(s,now)]
interval={"id":str(uuid.uuid4()).upper(),"startedAt":iso(s),"lastActivityAt":iso(now),"validatedActive":mins*60,
  "workSegments":segs,"excludedGaps":[],"settings":settings,"notificationSent":True}
uptime=time.clock_gettime(time.CLOCK_UPTIME_RAW)
data={"settings":settings,"timer":{"mode":"active","interval":interval},"history":history,
      "savedAt":iso(now),"savedSystemUptime":uptime}
json.dump(data,open(out,"w"),indent=1)
print(len(history),"records")
