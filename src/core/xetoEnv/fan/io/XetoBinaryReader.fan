//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   8 Aug 2023  Brian Frank  Creation
//

using concurrent
using util
using xeto
using haystack::Marker
using haystack::NA
using haystack::Remove
using haystack::Ref

**
** Reader for Xeto binary encoding of specs and data
**
@Js
class XetoBinaryReader : XetoBinaryConst, NameDictReader
{

//////////////////////////////////////////////////////////////////////////
// Constructor
//////////////////////////////////////////////////////////////////////////

  new make(XetoTransport transport, InStream in)
  {
    this.names = transport.names
    this.maxNameCode = transport.maxNameCode
    this.in = in
  }

//////////////////////////////////////////////////////////////////////////
// Remote Env Bootstrap
//////////////////////////////////////////////////////////////////////////

  internal RemoteEnv readRemoteEnvBootstrap()
  {
    verifyU4(magic, "magic")
    verifyU4(version, "version")
    readNameTable
    registry := readRegistry
    return RemoteEnv(names, registry) |env|
    {
      sys := readLib(env)
      registry.map["sys"].set(sys)
      verifyU4(magicEnd, "magicEnd")
    }
  }

  private Void readNameTable()
  {
    max := readVarInt
    for (i := 1; i<=max; ++i)
      names.add(in.readUtf)
  }

  private RemoteRegistry readRegistry()
  {
    acc := RemoteRegistryEntry[,]
    while (true)
    {
      nameCode := readVarInt
      if (nameCode == 0) break
      name := names.toName(nameCode)
      acc.add(RemoteRegistryEntry(name))
    }
    return RemoteRegistry(acc)
  }

//////////////////////////////////////////////////////////////////////////
// Lib
//////////////////////////////////////////////////////////////////////////

  private XetoLib readLib(MEnv env)
  {
    lib := XetoLib()

    verifyU4(magicLib, "magicLib")
    nameCode  := readName
    meta      := readMeta
    loader    := RemoteLoader(env, nameCode, meta)
    readTypes(loader)
    verifyU4(magicLibEnd, "magicLibEnd")

    return loader.loadLib
  }

  private Void readTypes(RemoteLoader loader)
  {
    while (true)
    {
      nameCode := readName
      if (nameCode < 0) break
      x := loader.addType(nameCode)
      readSpec(loader, x)
    }
  }

  private Void readSpec(RemoteLoader loader, RemoteLoaderSpec x)
  {
    x.base     = readSpecRef
    x.type     = readSpecRef
    x.metaOwn  = readMeta
    x.slotsOwn = readSlots(loader, x)
    x.flags    = readVarInt
   }

  private RemoteLoaderSpec[]? readSlots(RemoteLoader loader, RemoteLoaderSpec parent)
  {
    size := readVarInt
    if (size == 0) return null
    acc := RemoteLoaderSpec[,]
    acc.capacity = size
    size.times
    {
      name := readName
      x := loader.makeSlot(parent, name)
      readSpec(loader, x)
      acc.add(x)
    }
    return acc
  }

  private RemoteLoaderSpecRef? readSpecRef()
  {
    // first byte is slot path depth:
    //  - 0: null
    //  - 1: top-level type like "foo::Bar"
    //  - 2: slot under type like "foo::Bar.baz"
    //  - 3: "foo::Bar.baz.qux"

    depth := read
    if (depth == 0) return null

    ref := RemoteLoaderSpecRef()
    ref.lib  = readName
    ref.type = readName
    if (depth > 1)
    {
      ref.slot = readName
      if (depth > 2)
      {
        moreSize := depth - 2
        ref.more = Int[,]
        ref.more.capacity = moreSize
        moreSize.times { ref.more.add(readName) }
      }
    }

    return ref
  }

//////////////////////////////////////////////////////////////////////////
// Values
//////////////////////////////////////////////////////////////////////////

  override Obj readVal()
  {
    ctrl := in.readU1
    switch (ctrl)
    {
      case ctrlMarker:     return Marker.val
      case ctrlNA:         return NA.val
      case ctrlRemove:     return Remove.val
      case ctrlTrue:       return true
      case ctrlFalse:      return false
      case ctrlName:       return names.toName(readName)
      case ctrlStr:        return readUtf
      case ctrlUri:        return readUri
      case ctrlRef:        return readRef
      case ctrlDate:       return readDate
      case ctrlTime:       return readTime
      case ctrlDateTimeI4: return readDateTimeI4
      case ctrlDateTimeI8: return readDateTimeI8
      case ctrlNameDict:   return readNameDict
      case ctrlSpecRef:    return readSpecRefVal
      default:             throw IOErr("obj ctrl 0x$ctrl.toHex")
    }
  }

  private Uri readUri()
  {
    Uri.fromStr(readUtf)
  }

  private Ref readRef()
  {
    Ref.make(readUtf, null)
  }

  private Date readDate()
  {
    Date(in.readU2, Month.vals[in.read-1], in.read)
  }

  private Time readTime()
  {
    Time.fromDuration(Duration(in.readU4 * 1ms.ticks))
  }

  private DateTime readDateTimeI4()
  {
    DateTime.makeTicks(in.readS4*1sec.ticks, readTimeZone)
  }

  private DateTime readDateTimeI8()
  {
    DateTime.makeTicks(in.readS8, readTimeZone)
  }

  private TimeZone readTimeZone()
  {
    TimeZone.fromStr(readVal)
  }

  private Obj readSpecRefVal()
  {
    // TODO: how to turn this into direct reference to XetoSpec?
    ref := readSpecRef
    return "TODO"
  }

  private NameDict readNameDict()
  {
    size := readVarInt
    spec := null
    return names.readDict(size, this, spec)
  }

  override Int readName()
  {
    code := readVarInt
    if (code != 0) return code

    code = readVarInt
    name := readUtf
    names.set(code, name) // is now sparse
    return code
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  private Int read()
  {
    in.readU1
  }

  private Str readUtf()
  {
    in.readUtf
  }

  private NameDict readMeta()
  {
    verifyU1(ctrlNameDict, "ctrlNameDict for meta")  // readMeta is **with** the ctrl code
    return readNameDict
  }

  private Void verifyU1(Int expect, Str msg)
  {
    actual := in.readU1
    if (actual != expect) throw IOErr("Invalid $msg: 0x$actual.toHex != 0x$expect.toHex")
  }

  private Void verifyU4(Int expect, Str msg)
  {
    actual := in.readU4
    if (actual != expect) throw IOErr("Invalid $msg: 0x$actual.toHex != 0x$expect.toHex")
  }

  private Int readVarInt()
  {
    v := in.readU1
    if (v == 0xff)           return -1
    if (v.and(0x80) == 0)    return v
    if (v.and(0xc0) == 0x80) return v.and(0x3f).shiftl(8).or(in.readU1)
    if (v.and(0xe0) == 0xc0) return v.and(0x1f).shiftl(8).or(in.readU1).shiftl(16).or(in.readU2)
    return in.readS8
  }

//////////////////////////////////////////////////////////////////////////
// Fields
//////////////////////////////////////////////////////////////////////////

  private const NameTable names
  private const Int maxNameCode
  private InStream in
}

