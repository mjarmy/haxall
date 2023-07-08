//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   8 Jul 2023  Brian Frank  Creation
//

using util
using xeto

**
** Walk thru all the dict AST instances and add inferred tags
**
**
@Js
internal class InferData : Step
{
  override Void run()
  {
    ast.walk |node|
    {
      if (node.nodeType === ANodeType.dict) infer(node)
    }
  }

  private Void infer(ADict dict)
  {
    inferId(dict)
    inferSpecSlots(dict)
  }

  private Void inferId(ADict dict)
  {
    if (dict.id == null) return

    // make id qualified if this is lib data
    id := dict.id.toStr
    if (isLib) id = lib.name + "::" + id

    // add "id" tag with Ref scalar value
    loc := dict.loc
    ref := env.ref(id, null)
    if (dict.has("id")) err("Named dict cannot have explicit id tag", loc)
    dict.set("id", AScalar(loc, sys.ref, id, ref))
  }

  private Void inferSpecSlots(ADict dict)
  {
    spec := dict.typeRef?.deref
    if (spec == null) return

    spec.cslots.each |slot|
    {
      inferSpecSlot(dict, slot)
    }
  }

  private Void inferSpecSlot(ADict dict, CSpec slot)
  {
    if (dict.has(slot.name)) return

    // we haven't run InheritMeta yet, so this is awkward....
    // TODO: we need to run InheritMeta before Reify
    CSpec cspec := slot
    if (slot.isAst)
    {
      val := ((ASpec)slot).metaGet("val") as AScalar
      if (val != null)
      {
        dict.set(slot.name, val)
        return
      }
      cspec = slot.ctype
    }

    val := cspec.cmeta.get("val")
    if (val != null)
      dict.set(slot.name, AScalar(dict.loc, null, val.toStr, val))
  }

}