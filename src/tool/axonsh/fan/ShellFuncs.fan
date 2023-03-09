//
// Copyright (c) 2023, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   25 Jan 2023  Brian Frank  Creation
//

using data
using haystack
using axon
using folio

**
** Axon shell specific functions
**
const class ShellFuncs : AbstractShellFuncs
{
  ** Exit the shell.
  @Axon static Obj? quit()
  {
    cx.isDone = true
    return noEcho
  }

  ** Set the show error trace flag.
  @Axon static Obj? showTrace(Bool flag)
  {
    cx.showTrace = flag
    return noEcho
  }

  ** Print help summary or help on a specific command.
  ** Examples:
  **    help()        // print summary
  **    help(using)   // print help for the using function
  @Axon static Obj? help(Obj? func := null)
  {
    out := cx.out

    if (func == null)
    {
      out.printLine
      out.printLine("?, help            Print this help summary")
      out.printLine("quit, exit, bye    Exit the shell")
      out.printLine("help(func)         Help on a specific function")
      out.printLine("helpAll()          Print summary of all functions")
      out.printLine("print(val)         Pretty print value")
      out.printLine("showTrace(flag)    Toggle the show err trace flag")
      out.printLine("scope()            Print variables in scope")
      out.printLine("using()            Print data libraries in use")
      out.printLine("using(qname)       Import given data library")
      out.printLine("load(file)         Load virtual database")
      out.printLine("read(filter)       Read rec as dict from virtual database")
      out.printLine("readAll(filter)    Read recs as grid from virtual database")
      out.printLine
      return noEcho
    }

    f := func as TopFn
    if (f == null)
    {
      out.printLine("Not a top level function: $func [$func.typeof]")
      return noEcho
    }

    s := StrBuf()
    s.add(f.name).add("(")
    f.params.each |p, i|
    {
      if (i > 0) s.add(", ")
      s.add(p.name)
      if (p.def != null) s.add(":").add(p.def)
    }
    s.add(")")

    sig := s.toStr
    doc := funcDoc(f)

    out.printLine
    out.printLine(sig)
    if (doc != null) out.printLine.printLine(doc)
    out.printLine
    return noEcho
  }

  ** Print help summary of every function
  @Axon static Obj? helpAll()
  {
    out := cx.out
    names := cx.funcs.keys.sort
    nameMax := maxStr(names)

    out.printLine
    names.each |n|
    {
      f := cx.funcs[n]
      if (isNoDoc(f)) return
      d := docSummary(funcDoc(f) ?: "")
      out.printLine(n.padr(nameMax) + " " + d)
    }
    out.printLine
    return noEcho
  }

  ** Pretty print the given value.
  @Axon static Obj? print(Obj? val := null, Obj? opts := null)
  {
    cx.print(val, opts)
    return noEcho
  }

  ** Print the variables in scope
  @Axon static Obj? scope()
  {
    out := cx.out
    vars := cx.varsInScope
    names := vars.keys.sort
    nameMax := maxStr(names)

    out.printLine
    vars.keys.sort.each |n|
    {
      out.printLine("$n:".padr(nameMax+1) + " " + vars[n])
    }
    out.printLine
    return noEcho
  }

  ** Import data library into scope.
  **
  ** Examples:
  **   using()                // list all libraries currently in scope
  **   using("phx.points")    // import given library into scope
  **   using("*")             // import every library installed
  @Axon static Obj? _using(Str? qname := null)
  {
    /*
    out := cx.session.out

    if (qname == "*")
    {
      cx.data.libsInstalled.each |x| { _using(x) }
      return noEcho
    }

    if (qname != null)
    {
      cx.importDataLib(qname)
      out.printLine("using $qname")
      return noEcho
    }

    out.printLine
    cx.libs.keys.sort.each |x| { out.printLine(x) }
    out.printLine
    */
    return noEcho
  }

  ** Get library by qname (does not add it to using)
  @Axon static DataLib datalib(Str qname)
  {
    cx.data.lib(qname)
  }

//////////////////////////////////////////////////////////////////////////
// Load
//////////////////////////////////////////////////////////////////////////

  **
  ** Load in-memory database from local file.  The file is identified using
  ** an URI with Unix forward slash conventions.  The file must have one
  ** of the following file extensions: zinc, json, trio, or csv.
  ** Each record should define an 'id' tag, or if missing one will
  ** assigned automatically.
  **
  ** Examples:
  **   load(`folder/site.json`)
  **
  @Axon static Obj? load(Obj arg)
  {
    uri := arg as Uri ?: throw ArgErr("Load file must be Uri, not $arg.typeof")
    file := File(uri)

    echo("LOAD: loading '$file.osPath' ...")
    grid := readFile(file)

    // map grid into byId table
    diffs := Diff[,]
    grid.each |Dict rec|
    {
      id := rec.id
      rec = Etc.dictRemoveAll(rec, ["id", "mod"])
      diffs.add(Diff.makeAdd(rec, id))
    }
    cx.db.commitAll(diffs)

    echo("LOAD: loaded $grid.size recs")
    return noEcho
  }

  private static Grid readFile(File file)
  {
    switch (file.ext)
    {
      case "zinc": return ZincReader(file.in).readGrid
      case "json": return JsonReader(file.in).readGrid
      case "trio": return TrioReader(file.in).readGrid
      case "csv":  return CsvReader(file.in).readGrid
      default:     throw ArgErr("ERROR: unknown file type [$file.osPath]")
    }
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  private static Int maxStr(Str[] strs)
  {
    strs.reduce(0) |acc,s| { s.size.max(acc) }
  }

  private static Bool isNoDoc(TopFn f)
  {
    if (f.meta.has("nodoc")) return true
    if (f is FantomFn) return ((FantomFn)f).method.hasFacet(NoDoc#)
    return false
  }

  private static Str? funcDoc(TopFn f)
  {
    doc := f.meta["doc"] as Str
    if (doc != null) return doc.trimToNull
    if (f is FantomFn) return ((FantomFn)f).method.doc
    return null
  }

  private static Str? docSummary(Str t)
  {
    // this code is copied from defc::CFandoc - should be moved into haystack
    if (t.isEmpty) return ""

    semicolon := t.index(";")
    if (semicolon != null) t = t[0..<semicolon]

    colon := t.index(":")
    while (colon != null && colon + 1 < t.size && !t[colon+1].isSpace)
      colon = t.index(":", colon+1)
    if (colon != null) t = t[0..<colon]

    period := t.index(".")
    while (period != null && period + 1 < t.size && !t[period+1].isSpace)
      period = t.index(".", period+1)
    if (period != null) t = t[0..<period]

    return t.replace("\n", " ").trim
  }

}

**************************************************************************
** Absstract ShellFuncs
**************************************************************************

abstract const class AbstractShellFuncs
{
  internal static Str noEcho() { ShellContext.noEcho }

  internal static ShellContext cx() { AxonContext.curAxon }

}

