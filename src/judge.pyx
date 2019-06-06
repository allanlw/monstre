# This bit is implemented in python, because the algorithm requires
# comparison of pointers.

import json
import os
import sys
import collections
import itertools
import operator
import string
from functools import reduce

class Node:
  def __init__(self, type, value, children):
    self.type = type
    self.value = value.encode("ascii") if value is not None else None
    self.children = children
    self.cont = None
  def __repr__(self):
    r = self.type
    if self.value is not None:
      r += " " + repr(self.value)
    if self.children is not None:
      r += " " + ",".join(map(lambda x: "(" + repr(x) + ")", self.children))
    return r
  def alphabet(self):
    queue = [self]
    result = set()
    while len(queue) > 0:
      a = queue.pop(0)
      if a.type == "SAny":
        result |= set(a.encode("ascii") for a in string.printable)
      elif a.type == "SEmpty":
        continue
      elif a.type == "SConstant":
        result.add(a.value)
      else:
        queue += a.children
    return result

PWState = collections.namedtuple("PWState", ["ip", "input", "priority"])
WPFrame = collections.namedtuple("WPFrame", ["w", "p"]) # w is a string, p is a LIST of pointers
# H is the history, a list of sorted pointer lists, and f is a list of wP frams
# Holy shit why did they need to define like 10billion machines
HFState = collections.namedtuple("HFState", ["H", "f"])

# t.cont has ALREADY BEEN ASSIGNED
# assign cont value for children, then recurse
def assignCont(t):
  if t.type == "SConcat":
    t.children[0].cont = t.children[1]
    t.children[1].cont = t.cont
  elif t.type == "SAlternation":
    t.children[0].cont = t.cont
    t.children[1].cont = t.cont
  elif t.type == "SKleen":
    t.children[0].cont = t
  for child in t.children:
    assignCont(child)

# Takes a PWState and returns a list of next possible PWStates
def possibleNextPWStates(s):
  res = []
  if s.ip.type == "SEnd":
    pass # Termination state
  elif s.ip.type == "SAlternation":
    res.append(PWState(s.ip.children[0], s.input, 1))
    res.append(PWState(s.ip.children[1], s.input, 1))
  elif s.ip.type == "SKleen":
    # The priority for the child state is set lower, so that non-loop
    # conditions will be evaluated first in derive and a state will repeat itself
    res.append(PWState(s.ip.cont, s.input, 1))
    res.append(PWState(s.ip.children[0], s.input, 2))
  elif s.ip.type == "SConcat":
    res.append(PWState(s.ip.children[0], s.input, 1))
  elif s.ip.type == "SEmpty":
    # Low priority for the same reason as the child in SKleen
    res.append(PWState(s.ip.cont, s.input, 2))
  elif s.ip.type == "SConstant":
    if s.input.startswith(s.ip.value):
      res.append(PWState(s.ip.cont, s.input[1:], 1))
  elif s.ip.type == "SAny": # SAny is a specical form of SConstant that matches any character
    if len(s.input) > 0:
      res.append(PWState(s.ip.cont, s.input[1:], 1))
  else:
    raise ValueError("WTF " + s.ip.type)
  return res

# Takes a Node and 'evolves' it.
# Returns a list of possible next nodes if there has been no input
# This is a stupid name for the function
# This function needs protection against infinite recursion
def evolve(p):
  s = PWState(p, b"", 1)
  ns = possibleNextPWStates(s)
  return [(x.ip,x.priority) for x in ns]

# Takes a character a and a list of references to Nodes
# Returns a list of references to Nodes
# This is another stupid name for the function
# ASSUMPTION: b in the paper definition for this is an input symbol, not some other node
# NOTE: The paper defines this function recursively, but here it is defined
# iteratively, so that python's max recursion depth can be avoided
def derive(a, lp):
  result = []
  # States is a list of (node ref, priority) pairs
  # The priority ensures that prospective new states are alawys evaluated first
  # and that the machine will enter a steady state loop if such a loop exists
  states = [(x, 1) for x in lp]

  # Set of states that the machine has visisted. If repeated we bork
  seen = set()

  while len(states) > 0:
    this_round = tuple((id(x),y) for (x,y) in states)
    if this_round in seen:
      if stupid_global_verbose != 0:
        print("Breaking out of loop: did find {0} result(s) though".format(len(result)))
        sys.stdout.flush()
      break
    seen.add(this_round)
    head = states[0]
    tail = states[1:]
    if head[0].type == "SConstant":
      if head[0].value == a:
        result.append(head[0].cont)
      states = tail
    elif head[0].type == "SAny": # SAny is a special type of node that accepts any character in the alphabet
      result.append(head[0].cont)
      states = tail
    else:
      states = tail + evolve(head[0]) # Paper does it the other way, but order doesn't matter
    states.sort(key=lambda a: a[1])
  return result

# Takes a WPFrame and returns a list of next possible WPFrames
def nextWPFrames(wp, alphabet):
  return [WPFrame(wp.w + a, derive(a, wp.p)) for a in alphabet]

# takes a list of /references/ to nodes and returns a sorted tuple of /ids/
def toH(P):
  return tuple(sorted(id(x) for x in P))

# In HFStates, H is a /set/ of /sorted/ pointer lists (see toH)
# and f is a list of /current/ pointers
def nextHFState(hf, alphabet):
  firstWPState = hf.f[0]
  nextWPStates = nextWPFrames(firstWPState, alphabet)
  newH = hf.H
  newWPFrames = hf.f[1:]
  for frame in nextWPStates:
    h = toH(frame.p)
    if h in hf.H: continue
    newH.add(h)
    newWPFrames.append(frame)
  return HFState(newH, newWPFrames)

def isTerminationHFState(hf):
  if len(hf.f) == 0:
    return True, False
  # the other termination state occurs when two of the
  # pointers in the pointer set of the first WPState can evolve to the
  # same pointer
  firstWPState = hf.f[0]
  evolved = [map(lambda q: q[0], a) for a in map(evolve, firstWPState.p)]
  for p0, p1 in itertools.combinations(evolved, 2):
    for a in p0:
      if a in p1:
        return True, True
  return False, None

def analyzeRegex(tree):
  # initial state
  hfstate = HFState(set(), [WPFrame(b"", [tree])])

  alphabet = tree.alphabet()
  if stupid_global_verbose != 0:
    print(alphabet)
    sys.stdout.flush()

  while True:
    isterm, res = isTerminationHFState(hfstate)
    if isterm: return res
    hfstate = nextHFState(hfstate, alphabet)

def loadNode(j):
  if isinstance(j, str):
    return Node(j, None, ())
  assert isinstance(j, dict)
  keys = list(j.keys())
  assert len(keys) == 1
  kv = j[keys[0]]
  if isinstance(kv, str) and kv != "SAny":
    return Node(keys[0], kv, ())
  elif isinstance(kv, list):
    return Node(keys[0], None, tuple(map(loadNode, kv)))
  else:
    return Node(keys[0], None, (loadNode(kv),))

# Judges a regex tree (as a json object)
# Returnes "vulnerable" or "notvulnerable"
def judge(j):
  k = j.decode("ascii")
  try:
    x = json.loads(k)
  except RuntimeError:
    return (b"error")
  t = loadNode(x)
  t.cont = Node("SEnd", None, ())
  assignCont(t)
  vulnerable = analyzeRegex(t)
  if vulnerable:
    return(b"vulnerable")
  else:
    return(b"notvulnerable")

stupid_global_string_buffer = ""
stupid_global_verbose = 0
cdef public const char * judgeC(const char * j, int verbose):
  global stupid_global_verbose, stupid_global_string_buffer
  stupid_global_verbose = verbose
  stupid_global_string_buffer = judge(j)
  return stupid_global_string_buffer
