"""Initial routing compiler regressions. Run: python3 tools/test_c64_routes.py."""
import unittest
from types import SimpleNamespace as Room

from c64_routes import bake_routes, bridge_variants, ROUTE_PORTALS_HOME, ROUTE_DOORS_HOME


def room(x, y, w, h):
    return Room(x0=x, y0=y, w=w, h=h)


class Routing(unittest.TestCase):
    def bake(self, rooms, w, h, tiles=None, paper=None, decks=(), portals=()):
        classes = [0] * 128
        classes[16] = 1
        classes[80] = 3
        return bake_routes(rooms, tiles or [112] * (w*h), paper or [5] * (w*h),
                           w, h, classes, {1, 3}, set(decks), portals)

    def test_chain_and_unreachable_room(self):
        rs = [room(0,0,2,2), room(2,0,2,2), room(4,0,2,2), room(9,0,1,2)]
        data = self.bake(rs,10,2)
        hops = data[48:304]
        self.assertEqual(hops[2],1)
        self.assertEqual(hops[2*16],1)
        self.assertEqual(hops[3],255)
        self.assertEqual(hops[0],255)
        self.assertEqual(data[304:306],bytes([2,4]))

    def test_closed_deck_and_built_water(self):
        rs = [room(0,0,2,1),room(2,0,2,1)]
        paper = [5,6,6,5]
        closed = self.bake(rs,4,1,paper=paper,decks=[(1,0),(2,0)])
        self.assertEqual(closed[49],255)
        opened = self.bake(rs,4,1,tiles=[112,81,81,112],paper=paper)
        self.assertEqual(opened[49],1)

    def test_portal_links_blocked_wall(self):
        rs = [room(0,0,2,2),room(2,0,2,2)]
        data = self.bake(rs,4,2,tiles=[16]*8,portals=[(1,0)])
        self.assertEqual(data[0],0)
        self.assertEqual(data[24],1)
        self.assertEqual(data[49],1)
        self.assertEqual(data[304],0)

    def test_bfs_ties_use_room_order(self):
        rs = [room(0,0,2,2),room(2,0,2,2),room(0,2,2,2),room(2,2,2,2)]
        self.assertEqual(self.bake(rs,4,4)[48+3],1)

    def test_bridge_variants_and_reversible_patches(self):
        rs = [room(0,0,2,2),room(2,0,2,2)]
        decks = [(1,0),(2,0),(1,1),(2,1)]
        paper = [5,6,6,5]*2
        classes = [0]*128
        initial, program, images, size = bridge_variants(
            rs,[112]*8,paper,4,2,classes,{1,3},decks,[])
        self.assertLessEqual(size,256)
        self.assertEqual(len(images),16)
        addresses = list(range(ROUTE_PORTALS_HOME,ROUTE_PORTALS_HOME+304))+list(range(ROUTE_DOORS_HOME,ROUTE_DOORS_HOME+514))
        indexes = {address:i for i,address in enumerate(addresses)}

        def patch(image,state,restore):
            out=bytearray(image)
            at=program[16+state]
            for group_at in program[at+1:at+1+program[at]]:
                page,count=program[group_at:group_at+2]
                for i in range(count):
                    index,old,new=program[group_at+2+3*i:group_at+5+3*i]
                    out[indexes[page*256+index]]=old if restore else new
            return bytes(out)

        for state,image in enumerate(images):
            terrain=[112]*8
            closed=set(decks)
            for i,(x,y) in enumerate(decks):
                if state & (1<<i):
                    terrain[y*4+x]=81
                    closed.remove((x,y))
            reference=bake_routes(rs,terrain,paper,4,2,classes,{1,3},closed,[])
            self.assertEqual(image[:304],reference[:304])
            # Reserved closed doorway slots never claim an open crossing.
            self.assertEqual(sum(image[354:378]),sum(reference[354:378]))
            for target in range(len(images)):
                self.assertEqual(patch(patch(image,state,True),target,False),images[target])
        self.assertEqual(initial,images[0])

    def test_patch_budget_fails_before_emitting_invalid_offsets(self):
        # Eight independent boundary bits cannot fit even the state index.
        decks=[(1,y) for y in range(8)]
        with self.assertRaises(ValueError):
            bridge_variants([room(0,0,2,8)], [112]*16,[5]*16,2,8,[0]*128,{1,3},decks,[])


if __name__ == '__main__':
    unittest.main()
