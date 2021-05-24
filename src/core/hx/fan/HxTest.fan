//
// Copyright (c) 2021, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   18 May 2021  Brian Frank  Creation
//

using haystack
using folio

**
** HxTest is a base class for writing Haxall tests which provide
** access to a booted runtime instance.  Annotate test methods which
** require a runtime with `HxRuntimeTest`.  This class uses the 'hxd'
** implementation for its runtime.
**
**   @HxRuntimeTest
**   Void testBasics()
**   {
**     x := addRec(["dis":"It works!"])
**     y := rt.db.readById(x.id)
**     verifyEq(y.dis, "It works!")
**   }
**
abstract class HxTest : HaystackTest
{

//////////////////////////////////////////////////////////////////////////
// Test Setup
//////////////////////////////////////////////////////////////////////////

  ** If '@HxRuntimeTest' configured then open `rt`
  override Void setup()
  {
    if (curTestMethod.hasFacet(HxRuntimeTest#)) rtStart
  }

  ** If '@HxRuntimeTest' configured then close down `rt`
  override Void teardown()
  {
    if (rtRef != null) rtStop
    tempDir.delete
  }

//////////////////////////////////////////////////////////////////////////
// Runtime (@HxRuntimeTest)
//////////////////////////////////////////////////////////////////////////

  ** Test runtime if '@HxRuntimeTest' configured on test method
  HxRuntime? rt(Bool checked := true)
  {
    if (rtRef != null || !checked) return rtRef
    throw Err("Runtime not started (ensure $curTestMethod marked @HxRuntimeTest)")
  }

  ** Reference for `rt`
  @NoDoc HxRuntime? rtRef

  ** Start a test runtime which is accessible via `rt` method.
  @NoDoc virtual Void rtStart()
  {
    if (rtRef != null) throw Err("Runtime already started!")
    facet := curTestMethod.facet(HxRuntimeTest#, false) as HxRuntimeTest
    rtRef = spi.start
  }

  ** Stop test runtime
  @NoDoc virtual Void rtStop()
  {
    if (rtRef == null) throw Err("Runtime not started!")
    spi.stop(rtRef)
    rtRef = null
  }

  ** Stop, then restart test runtime
  @NoDoc virtual Void rtRestart()
  {
    rtStop
    rtStart
  }

  ** Service provider interface
  @NoDoc virtual HxTestSpi spi() { spiDef }

  private once HxTestSpi spiDef()
  {
    // use hxd implementation
    Type.find("hxd::HxdTestSpi").make([this])
  }

//////////////////////////////////////////////////////////////////////////
// Folio Conveniences
//////////////////////////////////////////////////////////////////////////

  ** Convenience for 'readById' on `rt`
  Dict? readById(Ref id, Bool checked := true)
  {
    rt.db.readById(id, checked)
  }

  ** Convenience for commit to `rt`
  Dict? commit(Dict rec, Obj? changes, Int flags := 0)
  {
    rt.db.commit(Diff.make(rec, changes, flags)).newRec
  }

  ** Add a record to `rt` using the given map of tags.
  Dict addRec(Str:Obj? tags := Str:Obj?[:])
  {
    // strip out null
    tags = tags.findAll |v, n| { v != null }

    id := tags["id"]
    if (id != null)
      tags.remove("id")
    else
      id = Ref.gen
    return rt.db.commit(Diff.makeAdd(tags, id)).newRec
  }
}

**************************************************************************
** HxRuntimeTest
**************************************************************************

**
** Annotates a `HxTest` method to setup a test runtime instance
**
facet class HxRuntimeTest {}

**************************************************************************
** HxTestSpi
**************************************************************************

**
** HxTest service provider interface
**
@NoDoc
abstract class HxTestSpi
{
  new make(HxTest test) { this.test = test }
  HxTest test { private set }
  abstract HxRuntime start()
  abstract Void stop(HxRuntime rt)
}



