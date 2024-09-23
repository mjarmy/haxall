//
// Copyright (c) 2024, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   22 Sep 2024  Brian Frank  Creation
//

using xetoEnv

**
** DocSpec is the documentation for a Xeto spec
**
@Js
const class DocSpec : DocPage
{
  ** Constructor
  new make(|This| f) { f(this) }

  ** URI relative to base dir to page
  const override Uri uri

  ** Qualified name of this spec
  const Str qname

  ** Library name for this instance
  once Str libName() { XetoUtil.qnameToLib(qname) }

  ** Simple name of this instance
  once Str name() { XetoUtil.qnameToName(qname) }

  ** Page type
  override const DocPageType pageType

  ** Encode to a JSON object tree
  override Str:Obj encode()
  {
    obj := Str:Obj[:]
    obj.ordered  = true
    obj["page"]  = pageType.name
    obj["uri"]   = uri.toStr
    obj["qname"] = qname
    return obj
  }

  ** Decode from a JSON object tree
  static DocSpec doDecode(Str:Obj obj)
  {
    DocSpec
    {
      it.pageType = DocPageType.fromStr(obj.getChecked("page"))
      it.uri      = Uri.fromStr(obj.getChecked("uri"))
      it.qname    = obj.getChecked("qname")
    }
  }

}
