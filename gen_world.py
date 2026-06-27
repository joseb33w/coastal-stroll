#!/usr/bin/env python3
# One-off generator for world.json (the data-driven, chat-editable source of truth at runtime).
# Lays out a 4x4 chunk grid: city (rows 0-1) -> forest (row 2) -> beach (row 3).
import json, random
random.seed(7)

CITY_GROUND   = [0.40, 0.40, 0.43]
PARK_GROUND   = [0.34, 0.39, 0.34]
FOREST_GROUND = [0.20, 0.27, 0.15]
BEACH_GROUND  = [0.82, 0.74, 0.53]

TOWER_TINTS = [[0.47,0.48,0.51],[0.52,0.50,0.47],[0.43,0.46,0.52],[0.50,0.49,0.50],[0.46,0.47,0.49],[0.55,0.52,0.49]]

# library asset scales (measured headlessly — these packs ship at odd authored scales)
S_STREETLIGHT=5.0; S_BENCH=4.5; S_HYDRANT=3.2; S_TRAFFIC=5.5; S_TRASH=4.0
SC = {"tree":160,"tree2":160,"pine":280,"pine2":280,"birch":280,"rock":250,"rock2":250,"rockmoss":250,"bush":70,"palm":1.0,"palm2":1.0}

def tower(x,z,w,d,h,ti,crown=True):
    return {"type":"tower","pos":[x,z],"w":w,"d":d,"h":h,"color":TOWER_TINTS[ti%len(TOWER_TINTS)],"seed":round(random.uniform(0,9),2),"crown":crown}
def cab(x,z,rot): return {"type":"cab","pos":[x,z],"rot":rot}
def light(x,z): return {"url":"props/kk_city/streetlight.glb","pos":[x,z],"scale":S_STREETLIGHT}
def bench(x,z,rot=0): return {"url":"props/kk_city/bench.glb","pos":[x,z],"scale":S_BENCH,"rot":rot}
def hydrant(x,z): return {"url":"props/kk_city/firehydrant.glb","pos":[x,z],"scale":S_HYDRANT}
def traffic(x,z): return {"url":"props/kk_city/trafficlight_A.glb","pos":[x,z],"scale":S_TRAFFIC}
def trash(x,z): return {"url":"props/kk_city/trash_A.glb","pos":[x,z],"scale":S_TRASH}
def rockp(x,z,kind="rock"): return {"url":"props/q_unature/Rock_5.glb" if kind=="rock2" else "props/q_unature/Rock_1.glb","pos":[x,z],"scale":SC[kind]}
def road(): return {"prim":"box","pos":[0,0],"size":[7.2,0.06,20.0],"color":[0.13,0.13,0.15],"y":0.01}
def dash(z): return {"prim":"box","pos":[0,z],"size":[0.28,0.07,1.7],"color":[0.86,0.78,0.22],"y":0.02}
def sidewalk(x): return {"prim":"box","pos":[x,0],"size":[5.0,0.12,20.0],"color":[0.52,0.52,0.55],"y":0.0}
def grass(x,z,s=6.0): return {"prim":"box","pos":[x,z],"size":[s,0.08,s],"color":[0.30,0.40,0.22],"y":0.0}
def trail(): return {"prim":"box","pos":[0,0],"size":[3.6,0.06,20.0],"color":[0.42,0.34,0.22],"y":0.02}
def wetsand(z): return {"prim":"box","pos":[0,z],"size":[20.0,0.05,5.0],"color":[0.62,0.57,0.45],"y":0.0}
def scat(kind,count): return {"kind":kind,"count":count,"scale":SC[kind]}

cells=[]
def addcell(gx,gz,zone,ground,**kw):
    c={"cell":[gx,gz],"zone":zone,"ground":ground}
    c.update(kw); cells.append(c)

# ROW gz=0 : CITY CORE
addcell(0,0,"city",CITY_GROUND,
    props=[road(),sidewalk(-7.5),sidewalk(7.5),dash(-5),dash(0),dash(5),light(-7,-7),light(-7,7),hydrant(8,2),traffic(-7,-8)],
    buildings=[{"type":"bodega","pos":[-5.5,-4.0],"rot":0,"place":"bodega","name":"Corner Bodega"},
               tower(6.8,-6.5,6,6,17,0),tower(6.8,6.5,6,6,21,1,crown=False)],
    pedestrians=[{"pos":[6,1]},{"pos":[-7,3]}])
addcell(1,0,"city",CITY_GROUND,
    props=[road(),sidewalk(-7.5),sidewalk(7.5),dash(-6),dash(-2),dash(2),dash(6),light(-7,-6),light(7,6),bench(-6,6,90),trash(7,-2)],
    landmark={"url":"models/fountain.glb","pos":[-6.0,5.5],"collider":"box"},
    buildings=[tower(7.0,-6.8,6,6,24,2),tower(-7.0,-6.8,5.5,5.5,15,3)],
    pedestrians=[{"model":"models/npc_vendor.glb","pos":[-4.5,4.0],"radius":3.0},{"pos":[5,-3]},{"pos":[3,7]}])
addcell(2,0,"city",CITY_GROUND,
    props=[road(),sidewalk(-7.5),sidewalk(7.5),dash(-5),dash(0),dash(5),light(7,-7),light(-7,7),hydrant(-8,-3),traffic(7,8)],
    landmark={"url":"models/subway_entrance.glb","pos":[6.5,5.5],"collider":"box"},
    buildings=[{"type":"lobby","pos":[-5.8,-4.2],"rot":0,"place":"lobby","name":"Apartment Lobby","h":22,"seed":4.0},
               tower(6.5,-6.8,6,6,19,4),cab(0.0,-8.0,0)],
    pedestrians=[{"pos":[-6,3]},{"pos":[7,-4]},{"pos":[2,6]}])
addcell(3,0,"city",CITY_GROUND,
    props=[road(),sidewalk(-7.5),sidewalk(7.5),dash(-6),dash(-2),dash(2),dash(6),light(-7,-7),light(7,7),bench(7,3,90),trash(-7,5)],
    buildings=[{"type":"diner","pos":[0.0,-4.5],"rot":0,"place":"diner","name":"The Diner"},
               tower(-7.0,6.8,6,6,20,5),tower(7.0,6.8,5.5,5.5,16,1),cab(7.5,-2.0,8)],
    pedestrians=[{"pos":[-6,-3]},{"pos":[6,2]}])

# ROW gz=1 : CITY EDGE / PARK TRANSITION
addcell(0,1,"city",PARK_GROUND,
    props=[road(),sidewalk(-7.8),grass(-6,5,7),grass(6,-5,6),light(-7,-7),bench(-6,5),rockp(7,6),trash(7,-6)],
    scatter=[scat("tree",4),scat("bush",4)],
    buildings=[tower(-7.0,-7.0,6,6,18,3,crown=False)],
    pedestrians=[{"pos":[5,2]}])
addcell(1,1,"city",PARK_GROUND,
    props=[road(),grass(-6,4,8),grass(6,5,7),grass(-5,-6,6),bench(-6,3,90),bench(6,4,90),light(7,-7),rockp(-7,6,"rock2")],
    scatter=[scat("tree",6),scat("bush",5)],
    pedestrians=[{"pos":[5,-2]},{"pos":[-5,6]}])
addcell(2,1,"city",PARK_GROUND,
    props=[road(),grass(6,4,8),grass(-6,5,7),bench(6,4),light(-7,-7),rockp(7,-6),cab(-7.5,-7.0,5)],
    scatter=[scat("tree",6),scat("bush",4)],
    buildings=[tower(7.0,-7.2,5.5,5.5,17,2,crown=False)],
    pedestrians=[{"pos":[-5,3]},{"pos":[6,6]}])
addcell(3,1,"city",PARK_GROUND,
    props=[road(),grass(-6,4,8),grass(6,-5,7),bench(-6,4,90),light(7,7),rockp(6,5,"rock2"),trash(-7,-6)],
    scatter=[scat("tree",5),scat("bush",4)],
    pedestrians=[{"pos":[5,3]}])

# ROW gz=2 : FOREST
for gx in range(4):
    pr=[trail(), rockp(-7,-5), rockp(7,4,"rock2"), rockp(6,-6),
        {"url":"props/q_unature/CommonTree_1.glb","pos":[-7,-7],"scale":SC["tree"]},
        {"url":"props/q_unature/PineTree_1.glb","pos":[7,7],"scale":SC["pine"]}]
    peds=[{"pos":[4,2]}] if gx in (1,2) else []
    addcell(gx,2,"forest",FOREST_GROUND,
        props=pr,
        scatter=[scat("pine",10),scat("tree",8),scat("birch",6),scat("bush",8),scat("rock",4)],
        pedestrians=peds)

# ROW gz=3 : BEACH
for gx in range(4):
    pr=[wetsand(7.0), rockp(-7,-3), rockp(7,-2,"rock2"),
        {"url":"props/fs_terrain/beach_prop_tree_palm_1.glb","pos":[-6,-6],"scale":SC["palm"]},
        {"url":"props/fs_terrain/beach_prop_tree_palm_2.glb","pos":[6,-7],"scale":SC["palm2"]}]
    peds=[{"pos":[0,-3]}] if gx in (1,2) else []
    addcell(gx,3,"beach",BEACH_GROUND,
        props=pr,
        scatter=[scat("palm",3),scat("rock",4),scat("bush",2)],
        pedestrians=peds)

world={
    "mode":"chunk",
    "title":"Coastal Stroll",
    "grid":{"cell_size":20},
    "start_cell":[1,0],
    "goal":{"type":"reach_cell","target":[2,3]},
    "ambient":[0.62,0.66,0.72],
    "cells":cells,
}
with open("world.json","w") as f:
    json.dump(world,f,indent=1)
print("wrote world.json with", len(cells), "cells")
