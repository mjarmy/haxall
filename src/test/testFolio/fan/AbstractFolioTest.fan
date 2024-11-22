//
// Copyright (c) 2015, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   2 Nov 2015  Brian Frank  Creation
//

using concurrent
using haystack
using folio
using hxFolio

**
** AbstractFolioTest is base class for black box testing across
** all the different Folio implementations
**
class AbstractFolioTest : HaystackTest
{

//////////////////////////////////////////////////////////////////////////
// Test
//////////////////////////////////////////////////////////////////////////

  static const FolioTestImpl[] impls
  static
  {
    list := [FolioFlatFileTestImpl(), HxFolioTestImpl()]
    try
      list.addNotNull(Type.find("testSkyarcd::Folio3TestImpl", false)?.make)
    catch (Err e)
      e.trace
    try
      list.addNotNull(Type.find("haven::HavenFolioTestImpl", false)?.make)
    catch (Err e)
      e.trace

    impls = list
  }

  override Void teardown()
  {
    impls.each |impl| { impl.teardown() }
  }

  FolioTestImpl? curImpl

  Void allImpls()
  {
    impls.each |impl| { runImpl(impl) }
  }

  Void fullImpls()
  {
    impls.each |impl| { if (impl.isFull) runImpl(impl) }
  }

  Void runImpl(FolioTestImpl impl)
  {
    doMethod := typeof.method("do" + curTestMethod.name.capitalize)
    echo("-- Run:  $doMethod($impl.name) ...")
    curImpl = impl
    doMethod.callOn(this, [,])

    if (folio != null) close
    tempDir.delete

    curImpl = null
  }

//////////////////////////////////////////////////////////////////////////
// Folio Lifecycle
//////////////////////////////////////////////////////////////////////////

  virtual Folio? folio() { folioRef }
  Folio? folioRef

  virtual Folio open(FolioConfig? config := null)
  {
    if (folio != null) throw Err("Folio is already open!")
    if (config == null) config = toConfig
    folioRef = curImpl.open(this, config)
    return folio
  }

  FolioConfig toConfig(Str? idPrefix := null)
  {
    FolioConfig
    {
      it.dir      = tempDir
      it.log      = Log.get("test")
      it.idPrefix = idPrefix
    }
  }

  Void close()
  {
   if (folio == null) throw Err("Folio not open!")
   folio.close
   folioRef = null
  }

  Folio reopen(FolioConfig? config := null)
  {
    close
    return open(config)
  }

  Bool isHisSupported()
  {
    try
    {
      folio.his
      return true
    }
    catch (UnsupportedErr e)
    {
      return false
    }
  }

//////////////////////////////////////////////////////////////////////////
// Folio Utils
//////////////////////////////////////////////////////////////////////////

  Dict readById(Ref id)
  {
    folio.readById(id)
  }

  Dict addRec(Str:Obj tags)
  {
    id := tags["id"]
    if (id != null)
      tags.remove("id")
    else
      id = Ref.gen
    return folio.commit(Diff.makeAdd(tags, id)).newRec
  }

  Dict? commit(Dict rec, Obj? changes, Int flags := 0)
  {
    folio.commit(Diff.make(rec, changes, flags)).newRec
  }

  Void removeRec(Dict rec)
  {
    folio.commit(Diff.make(folio.readById(rec.id), null, Diff.remove))
  }

//////////////////////////////////////////////////////////////////////////
// verify methods
//////////////////////////////////////////////////////////////////////////

  Void verifyRecs(Dict a, Dict b)
  {
    if (curImpl.supportsRecIdentity)
      verifySame(a, b)
    else
      verifyDictEq(a, b)
  }

}

**************************************************************************
** FolioTestImpl
**************************************************************************

abstract const class FolioTestImpl
{
  abstract Str name()
  abstract Bool isFull()
  abstract Folio open(AbstractFolioTest t, FolioConfig config)

  ** Hook to tear down the test implementation
  virtual Void teardown() { }

  ** Return whether this Folio implementation has the concept of a current version.
  virtual Bool supportsCurVer() { return true }

  ** Return whether this Folio implementation should compare recs by
  ** verifySame(), or by verifyDictEq().
  virtual Bool supportsRecIdentity() { return true }

  ** Return whether this Folio implementation allows transient tags.
  virtual Bool supportsTransientTags() { return true }

  ** Return whether this Folio implementation uses the "mod" tag to support concurrency.
  virtual Bool supportsConcurrentModCheck() { return true }
}

const class FolioFlatFileTestImpl : FolioTestImpl
{
  override Str name() { "flatfile" }
  override Bool isFull() { false }
  override Folio open(AbstractFolioTest t, FolioConfig c) { FolioFlatFile.open(c) }
}

const class HxFolioTestImpl : FolioTestImpl
{
  override Str name() { "hx" }
  override Bool isFull() { true }
  override Folio open(AbstractFolioTest t, FolioConfig c) { HxFolio.open(c) }
}
