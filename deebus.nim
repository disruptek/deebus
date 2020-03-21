import std/macros
import std/sequtils
import std/strutils
import std/os
import std/nre

import dbus
import dbus/lowlevel

{.experimental: "dotOperators".}
{.experimental: "callOperator".}

type
  Interface* = object
    bus*: Bus
    path*: ObjectPath
    name*: string
    service*: string

  Method* = object
    iface*: Interface
    name*: string

when defined(deebusJson):
  import std/json
  proc toJson*(value: DbusValue): JsonNode =
    case value.kind
    of dtArray:
      result = newJArray()
      for v in mapIt(value.arrayValue, it.toJson):
        result.add v
    of dtBool:
      result = newJBool(value.boolValue)
    of dtDictEntry:
      result = newJArray()
      result.add value.dictKey.toJson
      result.add value.dictValue.toJson
    of dtDouble:
      result = newJFloat(value.doubleValue)
    of dtSignature:
      result = newJString(value.signatureValue.string)
    of dtUnixFd:
      result = newJInt(value.fdValue.int)
    of dtInt32:
      result = newJInt(value.int32Value)
    of dtInt16:
      result = newJInt(value.int16Value)
    of dtObjectPath:
      result = newJString(value.objectPathValue.string)
    of dtUint16:
      result = newJInt(value.uint16Value.int)
    of dtString:
      result = newJString(value.stringValue)
    of dtStruct:
      result = newJArray()
      for v in mapIt(value.structValues, it.toJson):
        result.add v
    of dtUint64:
      result = newJInt(value.uint64Value.int)
    of dtUint32:
      result = newJInt(value.uint32Value.int)
    of dtInt64:
      result = newJInt(value.int64Value)
    of dtByte:
      result = newJInt(value.byteValue.int)
    of dtVariant:
      result = value.variantValue.toJson
    else:
      result = newJNull()

proc getBus*(path: DBusValue): Bus =
  ## open a new bus connection at the given address
  var
    error: ptr DBusError
  let
    path = path.stringValue
    conn = dbus_connection_open(path.cstring, error)
  if conn == nil:
    error "unable to connect via " & path
  elif error != nil:
    error error.repr
  else:
    result = Bus(conn: conn)

converter toBool(b: dbus_bool_t): bool =
  result = cast[uint32](b) == 1

template queryBusImpl(meth: Method; args: typed): untyped =
  var
    msg = makeCall(meth.iface.service,
                   meth.iface.path, meth.iface.name, meth.name)
  for value in args.items:
    msg.append(value)
  let
    pending = meth.iface.bus.sendMessageWithReply(msg)
    reply = pending.waitForReply()
  reply.raiseIfError
  try:
    var
      iter = reply.iterate()
    result = iter.unpackCurrent(DBusValue)
  except DBusException: # i hate it
    result = asDbusValue(nil)

proc queryBus(meth: Method; args: varargs[DBusValue, asDbusValue]): DBusValue =
  queryBusImpl(meth, args)

proc queryBus(meth: Method; args: seq[DBusValue]): DBusValue =
  queryBusImpl(meth, args)

proc peer*(iface: Interface; name: string): Interface =
  ## yield the adjacent interface with the given name
  # Interface(name: name, path: iface.path, bus: iface.bus)
  result = iface
  result.name = name

proc toString*(value: DBusValue): string =
  ## turn an array of bytes ending in zero into a string
  for element in value.arrayValue:
    if element.byteValue == 0:
      break
    else:
      result.add element.byteValue.char

proc `$`*(iface: Interface): string = result = iface.name
proc `$`*(sig: Signature): string = result = sig.string
proc `$`*(path: ObjectPath): string = result = path.string

proc `$`(value: DBusValue): string =
  result = case value.kind
  of dtString:
    value.stringValue
  of dtObjectPath:
    value.objectPathValue.string
  of dtSignature:
    value.signatureValue.string
  else:
    dbus.`$`(value)

proc `==`(value: DBusValue; s: string): bool =
  if value.kind notin {dtString, dtObjectPath, dtSignature}:
    raise newException(ValueError, "bad value type: " & $value.kind)
  result = system.`==`($value, s)

proc `..`(a: Interface): Interface =
  ## parent interface
  result = a
  result.name = changeFileExt($a, "")
  if result.name.len == a.name.len:
    raise newException(Defect, "already at top level")

proc `..`(a: Interface; name: string): Interface =
  ## named peer interface
  result = a
  result.name = changeFileExt($a, "") & "." & name

proc `[]`*(iface: Interface; name: string): Method =
  ## get a method on the interface by name
  result = Method(iface: iface, name: name)

proc `path=`(iface: var Interface; path: ObjectPath) =
  ## switch to different path
  system.`=`(iface.path, path)

proc `path=`(iface: var Interface; path: string) =
  ## switch to different path
  system.`=`(iface.path, path.ObjectPath)

proc `path=`(iface: var Interface; path: DBusValue) =
  ## switch to different path
  system.`=`(iface.path, path.stringValue.ObjectPath)

proc `{}`*(iface: Interface; name: string): Method =
  ## fetch a method from the interface's org.freedesktop.DBus.Properties peer
  result = iface.peer("org.freedesktop.DBus.Properties")[name]

proc `/`*(iface: Interface, name: string): Interface =
  ## interface at child path
  var
    child = iface
  child.path = ObjectPath(child.path.string / name)
  result = child

proc `()`*(meth: Method; args: varargs[DBusValue, asDBusValue]): DBusValue =
  ## call a method with arbitrary arguments
  queryBusImpl(meth, args)

proc `.`(iface: Interface, name: string): Interface =
  ## child interface
  result = iface
  result.name &= "." & name

when false:
  proc `()`(path: var ObjectPath; args: varargs[string, `$`]) =
    var
      arguments: seq[string]
    for a in args.items:
      arguments.add a
    path = joinPath(args)

iterator items*(value: DBusValue): DBusValue =
  case value.kind
  of dtArray:
    for item in value.arrayValue.items:
      yield item
  else:
    raise newException(OSError, $value)

iterator pairs*(value: DBusValue): tuple[key: DBusValue; val: DBusValue] =
  case value.kind
  of dtArray:
    if value.arrayValueType.kind != dtDictEntry:
      raise newException(ValueError, "not a dictionary")
    for pair in value.items:
      yield (key: pair.dictKey, val: pair.dictValue)
  else:
    raise newException(OSError, $value)

when isMainModule:
  import std/logging
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)
