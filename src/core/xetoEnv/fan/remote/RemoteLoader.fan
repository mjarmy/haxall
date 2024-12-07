//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   9 Aug 2022  Brian Frank  Creation
//

using util
using concurrent
using xeto
using haystack::Dict
using haystack::Etc

**
** RemoteLoader is used to load a library serialized over a network
**
@Js
internal class RemoteLoader
{

//////////////////////////////////////////////////////////////////////////
// Constructor
//////////////////////////////////////////////////////////////////////////

  new make(MNamespace ns, Int libNameCode, MNameDict libMeta, Int flags)
  {
    this.ns          = ns
    this.names       = ns.names
    this.libName     = names.toName(libNameCode)
    this.libNameCode = libNameCode
    this.libMeta     = libMeta
    this.libVersion  = libMeta->version
    this.flags       = flags
  }

//////////////////////////////////////////////////////////////////////////
// Top
//////////////////////////////////////////////////////////////////////////

  XetoLib loadLib()
  {
    loadBindings

    depends := libMeta["depends"] ?: MLibDepend#.emptyList
    tops    := loadTops

    m := MLib(loc, libNameCode, libName, libMeta, flags, libVersion, depends, tops, instances, UnsupportedLibFiles.val)
    XetoLib#m->setConst(lib, m)
    return lib
  }

  RSpec addTop(Int nameCode)
  {
    name := names.toName(nameCode)
    x := RSpec(libName, null, nameCode, name)
    tops.add(name, x)
    return x
  }

  RSpec makeSlot(RSpec parent, Int nameCode)
  {
    name := names.toName(nameCode)
    x := RSpec(libName, parent, nameCode, name)
    return x
  }

  Void addInstance(Dict x)
  {
    id := x.id.id
    name := id[id.index(":")+2..-1]
    instances.add(name, x)
  }

//////////////////////////////////////////////////////////////////////////
// Factories
//////////////////////////////////////////////////////////////////////////

  private Void loadBindings()
  {
    // check if this library registers a new factory loader
    libVersion := libMeta->version
    if (bindings.needsLoad(libName, libVersion))
    {
      loader := bindings.load(libName, libVersion)
      tops.each |x|
      {
        if (x.flavor.isType) loader.loadSpec(bindings, x)
      }
    }
  }

  private SpecBinding assignBinding(RSpec x)
  {
    // check for custom factory if x is a type
    b := bindings.forSpec(x.qname)
    if (b != null) return b

    // fallback to dict/scalar factory
    isScalar := MSpecFlags.scalar.and(x.flags) != 0
    return isScalar ? GenericScalarBinding(x.qname) : bindings.dict
  }

//////////////////////////////////////////////////////////////////////////
// Specs
//////////////////////////////////////////////////////////////////////////

  private Str:XetoSpec loadTops()
  {
    specs := tops.map |x->XetoSpec| { loadSpec(x).asm }
    specs.each |spec| { reifySpecMeta(spec) }
    return specs
  }

  private RSpec loadSpec(RSpec x)
  {
    if (x.isLoaded) return x

    x.isLoaded = true
    x.base     = resolve(x.baseIn)
    x.metaOwn  = resolveMeta(x.metaOwnIn)

    if (x.base == null)
    {
      // sys::Obj
      x.meta  = x.metaOwn
      x.slotsOwn = loadSlotsOwn(x)
      x.slots = x.slotsOwn
    }
    else
    {
      // recursively load base and inherit
      if (x.base.isAst) loadSpec(x.base)
      x.meta = inheritMeta(x)
      x.slotsOwn = loadSlotsOwn(x)
      x.slots = inheritSlots(x)
      x.args  = loadArgs(x)
    }

    MSpec? m
    if (x.flavor.isType)
    {
      x.bindingRef = assignBinding(x)
      m = MType(loc, lib, qname(x), x.nameCode, x.name, x.base?.asm, x.asm, x.meta, x.metaOwn, x.slots, x.slotsOwn, x.flags, x.args, x.binding)
    }
    else if (x.flavor.isGlobal)
    {
      m = MGlobal(loc, lib, qname(x), x.nameCode, x.name, x.base.asm, x.base.asm, x.meta, x.metaOwn, x.slots, x.slotsOwn, x.flags, x.args)
    }
    else if (x.flavor.isMeta)
    {
      m = MMetaSpec(loc, lib, qname(x), x.nameCode, x.name, x.base.asm, x.base.asm, x.meta, x.metaOwn, x.slots, x.slotsOwn, x.flags, x.args)
    }
    else
    {
      x.type = resolve(x.typeIn).asm
      m = MSpec(loc, x.parent.asm, x.nameCode, x.name, x.base.asm, x.type, x.meta, x.metaOwn, x.slots, x.slotsOwn, x.flags, x.args)
    }
    XetoSpec#m->setConst(x.asm, m)
    return x
  }

  private Str qname(RSpec x)
  {
    StrBuf(libName.size + 2 + x.name.size).add(libName).addChar(':').addChar(':').add(x.name).toStr
  }

  private MNameDict resolveMeta(NameDict m)
  {
    // if emtpy
    if (m.isEmpty) return MNameDict.empty

    // resolve spec ref values
    m = m.map |v, n|
    {
      v is RSpecRef ? resolve(v).asm : v
    }

    // wrap
    return MNameDict(m)
  }

  private MSlots loadSlotsOwn(RSpec x)
  {
    // short circuit if no slots
    slots := x.slotsOwnIn
    if (slots == null || slots.isEmpty) return MSlots.empty

    // recursively load slot specs
    slots.each |slot| { loadSpec(slot) }

    // RSpec is a NameDictReader to iterate slots as NameDict
    dict := names.readDict(slots.size, x)
    return MSlots(dict)
  }

  private MNameDict inheritMeta(RSpec x)
  {
    // if we included effective meta from compound types use it
    if (x.metaIn != null) return resolveMeta(x.metaIn)

    own     := x.metaOwn         // my own meta
    base    := x.base.cmeta      // base spec meta
    inherit := x.metaInheritedIn // names to inherit from base

    // optimize when we can just reuse base
    if (own.isEmpty)
    {
      baseSize := 0
      base.each |v| { baseSize++ }
      if (baseSize == inherit.size) return base
    }

    // create effective meta from inherited names from base and my own
    acc := Str:Obj[:]
    inherit.each |n| { acc[n] = base.trap(n) }
    XetoUtil.addOwnMeta(acc, own)

    return MNameDict(names.dictMap(acc))
  }

  private MSlots inheritSlots(RSpec x)
  {
    // if we encoded inherited refs for and/or types, then use that
    if (x.slotsInheritedIn != null)
      return inheritSlotsFromRefs(x)

    // if my own slots are empty, I can just reuse my parent's slot map
    base := x.base
    if (x.slotsOwn.isEmpty)
    {
      // if (base === x.parent) return MSlots.empty

      if (base.isAst)
        return ((RSpec)base).slots ?: MSlots.empty // TODO: recursive base problem
      else
        return ((XetoSpec)base).m.slots
    }

    // simple single base class solution
    acc := Str:XetoSpec[:]
    acc.ordered = true
    x.base.cslots |slot|
    {
      if (acc[slot.name] == null) acc[slot.name] = slot.asm
    }
    x.slotsOwn.each |slot|
    {
      acc[slot.name] = slot
    }
    return MSlots(names.dictMap(acc))
  }

  private MSlots inheritSlotsFromRefs(RSpec x)
  {
    acc := Str:XetoSpec[:]
    acc.ordered = true
    x.slotsInheritedIn.each |ref|
    {
      slot := resolve(ref)
      if (slot.isAst) loadSpec(slot)
      if (acc[slot.name] == null) acc[slot.name] = slot.asm
    }
    x.slotsOwn.each |slot|
    {
      acc[slot.name] = slot
    }
    return MSlots(names.dictMap(acc))
  }

  private MSpecArgs loadArgs(RSpec x)
  {
    of := x.metaOwn["of"] as Ref
    if (of != null) return MSpecArgsOf(resolveRef(of))

    ofs := x.metaOwn["ofs"] as Ref[]
    if (ofs != null) return MSpecArgsOfs(ofs.map |ref->Spec| { resolveRef(ref) })

    return x.base.args
  }

  private Spec resolveRef(Ref ref)
  {
    // TODO: we can encode spec refs way better than a simple string
    // that has to get parsed again (see down below with RSpecRef)
    colons := ref.id.index("::")
    libName := ref.id[0..<colons]
    specName := ref.id[colons+2..-1]
    rref := RSpecRef(names.toCode(libName), names.toCode(specName), 0, null)
    return resolve(rref).asm
  }

//////////////////////////////////////////////////////////////////////////
// ReifyMeta
//////////////////////////////////////////////////////////////////////////

  private Void reifySpecMeta(XetoSpec spec)
  {
    // this is not ideal because we don't have all our types and
    // factories setup until after we have mapped RSpecs to XetoSpecs;
    // but at the very least we need to reify scalar default values
    if (spec.isDict)
    {
      spec.slotsOwn.each |slot| { reifySpecMeta(slot) }
      return
    }

    if (spec.isScalar)
    {
      reifySpecMetaScalarVal(spec)
    }
  }

  private Void reifySpecMetaScalarVal(XetoSpec spec)
  {
    // skip if already not a string
    val := spec.meta["val"]
    if (val == null || val isnot Str) return

    // skip if already mapped as Fantom string
    if (spec.binding.type === Str#) return

    try
    {
      // decode string to its scalar fantom instance
      val = spec.binding.decodeScalar(val.toStr, true)

      // use setConst to update the const meta/metaOwn fields
      mspec := spec.m
      MSpec#meta->setConst(mspec, metaSet(mspec.meta, "val", val))
      MSpec#metaOwn->setConst(mspec, metaSet(mspec.metaOwn, "val", val))
    }
    catch (Err e) echo("ERROR: cannot reify spec meta $spec\n" + e.traceToStr)
  }

  private MNameDict metaSet(MNameDict d, Str name, Obj val)
  {
    MNameDict(d.wrapped.map |v, n| { n == name ? val : v })
  }

//////////////////////////////////////////////////////////////////////////
// Resolve
//////////////////////////////////////////////////////////////////////////

  private CSpec? resolveStr(Str qname, Bool checked := true)
  {
    if (qname.startsWith(libName) && qname[libName.size] == ':')
    {
      return tops.getChecked(qname[libName.size+2..-1], checked)
    }
    else
    {
      return ns.spec(qname, checked)
    }
  }

  private CSpec? resolve(RSpecRef? ref)
  {
    if (ref == null) return null
    if (ref.lib == libNameCode)
      return resolveInternal(ref)
    else
      return resolveExternal(ref)
  }

  private CSpec resolveInternal(RSpecRef ref)
  {
    type := tops.getChecked(names.toName(ref.type))
    if (ref.slot == 0) return type

    slot := type.slotsOwnIn.find |s| { s.nameCode == ref.slot } ?: throw UnresolvedErr(ref.toStr)
    if (ref.more == null) return slot

    x := slot
    ref.more.each |moreCode|
    {
      x = x.slotsOwnIn.find |s| { s.nameCode == moreCode } ?: throw UnresolvedErr(ref.toStr)
    }
    return x
  }

  private XetoSpec resolveExternal(RSpecRef ref)
  {
    // should already be loaded
    lib := ns.lib(names.toName(ref.lib))
    type := (XetoSpec)lib.spec(names.toName(ref.type))
    if (ref.slot == 0) return type

    slot := type.m.slots.map.getByCode(ref.slot) ?: throw UnresolvedErr(ref.toStr)
    if (ref.more == null) return slot

    throw Err("TODO: $type $ref")
  }

//////////////////////////////////////////////////////////////////////////
// Fields
//////////////////////////////////////////////////////////////////////////

  const MNamespace ns
  const NameTable names
  const FileLoc loc := FileLoc("remote")
  const XetoLib lib := XetoLib()
  const Str libName
  const Int libNameCode
  const MNameDict libMeta
  const Version libVersion
  const SpecBindings bindings := SpecBindings.cur
  const Int flags
  private Str:RSpec tops := [:]              // addTops
  private Str:Dict instances := [:]          // addInstance (unreified)
}

