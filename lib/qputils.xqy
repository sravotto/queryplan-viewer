xquery version "1.0-ml";

(:
 : Copyright (c) 2019 John Snelson
 :
 : Licensed under the Apache License, Version 2.0 (the "License");
 : you may not use this file except in compliance with the License.
 : You may obtain a copy of the License at
 :
 :     http://www.apache.org/licenses/LICENSE-2.0
 :
 : Unless required by applicable law or agreed to in writing, software
 : distributed under the License is distributed on an "AS IS" BASIS,
 : WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 : See the License for the specific language governing permissions and
 : limitations under the License.
 :)

module namespace qputils = "http://marklogic.com/optic/qputils";
declare default function namespace "http://marklogic.com/optic/qputils";
declare namespace plan="http://marklogic.com/plan";
declare namespace xsi="http://www.w3.org/2001/XMLSchema-instance";
using namespace "http://www.w3.org/2005/xpath-functions";

declare variable $time-attrs := ("local-time","remote-time");
declare variable $memory-attrs := ("local-max-memory","remote-max-memory");

declare function format-time($v)
{
  fn:round-half-to-even(($v div 10000),2) || "ms"
};

declare function format-memory($v)
{
  let $n := xs:double($v)
  return switch(true())
  case $n > (1024 * 1024 * 1024) return fn:round-half-to-even($n div (1024 * 1024 * 1024),2) || "Gb"
  case $n > (1024 * 1024) return fn:round-half-to-even($n div (1024 * 1024),2) || "Mb"
  case $n > (1024) return fn:round-half-to-even($n div (1024),2) || "Kb"
  default return $n || "b"
};

declare function attrs9($map,$node)
{
  fn:fold-left(function($map, $a) {
      let $key := local-name($a)
      let $key := if($node/@type = "iri" and $key = "name") then "value" else $key
      return $map=>map:with($key, string($a))
    },
    $map,$node/@*[not(local-name(.) = ("static-type"))])
  =>(function($map){
    if($node/plan:rdf-val and not($node/@name)) then (
      attrs($map,$node/plan:rdf-val),
      if($node/plan:rdf-val/* or empty($node/plan:rdf-val/text())) then $map
      else $map
        =>map:with("value",string($node/plan:rdf-val))
    ) else $map
  })()
};

declare function attrs($map,$node,$skip)
{
  fn:fold-left(function($map, $a) {
      switch(true())
      case local-name($a) = $time-attrs return $map=>map:with(local-name($a), format-time($a))
      case local-name($a) = $memory-attrs return $map=>map:with(local-name($a), format-memory($a))
      default return $map=>map:with(local-name($a), string($a))
    },
    $map,$node/@*[not(local-name(.) = $skip)])
  =>(function($map){
    if($node/* or empty($node/text())) then $map
    else $map
      =>map:with("value",string($node))
  })()
};

declare function attrs($map,$node)
{
  attrs($map,$node,("static-type","column-number"))
};

declare function nameAndAttrs($map,$node)
{
  $map
  =>map:with("_name",local-name($node))
  =>attrs($node)
};

declare function makeTemplateViewGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>nameAndAttrs($node)
  =>( (: v9 :)
    fn:fold-left(function($map,$n) {
      let $key := "column"
      let $val := attrs(map:map(),$n)=>attrs($n/plan:graph-node)
      return $map=>map:with($key,($map=>map:get($key),$val))
    },?,$node/*[local-name(.) = ("template-column")])
  )()
  =>(
    fn:fold-left(function($map,$n) {
      let $key := local-name($n)
      let $val := attrs(map:map(),$n)=>attrs($n/(plan:name|plan:graph-node))
      return $map=>map:with($key,($map=>map:get($key),$val))
    },?,$node/*[local-name(.) = ("column","row","fragment","content")])
  )(),

  for $c at $pos in $node/*[not(local-name(.) = ("template-column","column","row","fragment","content"))]
  let $newID := concat($id, "_", $pos)
  return (
    let $maps := makeGraph($c,$newID)
    return (
      head($maps)=>map:with("_parent",$id),
      tail($maps)
    )
  )
};

declare function makeLiteralGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>map:with("_name","literal")
  =>map:with("value",string($node/plan:value))
  =>map:with("type",string($node/plan:value/@xsi:type))
};

declare function makeJoinFilter($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>nameAndAttrs($node)
  =>(
    fn:fold-left(function($map,$n) {
      $map=>map:with(local-name($n),attrs(map:map(),$n))
    },?,$node/*[local-name(.) = ("left","right")])
  )()
  =>(
    fn:fold-left(function($map,$n) {
      $map=>map:with(local-name($n/..),attrs(map:map(),$n))
    },?,$node/(plan:left-graph-node|plan:right-graph-node)/plan:graph-node)
  )()
  =>map:with("condition", string-join((
      string($node/(plan:left|plan:left-graph-node/plan:graph-node)/@column-index), string($node/@op),
      if($node/(plan:right|plan:right-graph-node))
      then string($node/(plan:right|plan:right-graph-node/plan:graph-node)/@column-index)
      else "expr"
    ))),

  for $c at $pos in $node/plan:right-expr/plan:*
  let $newID := concat($id, "_", $pos)
  return (
    let $maps := makeGraph($c,$newID)
    return (
      head($maps)=>map:with("_parent",$id),
      tail($maps)
    )
  )
};

declare function makeTripleGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>nameAndAttrs($node)
  =>(
    switch(version($node))
    case 9 return 
      fn:fold-left(function($map,$n) {
        $map=>map:with(local-name($n/..),attrs9(map:map(),$n))
      },?,$node/*[local-name(.) = ("subject","predicate","object","graph","fragment")]/plan:graph-node)
    default return
      fn:fold-left(function($map,$n) {
        $map=>map:with(local-name($n),attrs(map:map(),$n))
      },?,$node/*[local-name(.) = ("subject","predicate","object","graph","fragment")])
  )(),

  for $c at $pos in $node/*[not(local-name(.) = ("subject","predicate","object","graph","fragment"))]
  let $newID := concat($id, "_", $pos)
  return (
    let $maps := makeGraph($c,$newID)
    return (
      head($maps)=>map:with("_parent",$id),
      tail($maps)
    )
  )
};

declare function makeOrderGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>nameAndAttrs($node),

  for $c at $pos in $node/*[not(local-name(.) = ("order-spec"))]
  let $newID := concat($id, "_", $pos)
  return (
    let $maps := makeGraph($c,$newID)
    return (
      head($maps)=>map:with("_parent",$id),
      tail($maps)
    )
  )
};

declare %private function version($node)
{
  if($node/plan:expr) then 9
  else if($node/plan:elems) then 9
  else if($node/plan:*/plan:graph-node) then 9
  else 10
};

declare function makeProjectGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>nameAndAttrs($node),

  let $children :=
    switch(version($node))
    case 9 return $node/plan:expr/*
    default return $node/*[not(self::plan:column)]

  for $c at $pos in $children
  let $newID := concat($id, "_", $pos)
  return (
    let $maps := makeGraph($c,$newID)
    return (
      head($maps)=>map:with("_parent",$id),
      tail($maps)
    )
  )
};

declare function makeJoinGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>map:with("_name",string($node/(@type|@join-type)))
  =>attrs($node,("static-type","type","join-type"))
  =>map:with("condition", string-join(
    let $conditions :=
      switch(version($node))
      case 9 return $node/plan:join-info/plan:hash
      default return $node/plan:hash

    for $c at $pos in $conditions
    return (
      if($pos=1) then () else " and ",
      string($c/@left), string($c/(@op|@operator)), string($c/@right)
    ))),

  let $subs :=
    switch(version($node))
    case 9 return ($node/plan:elems/*,
      if(contains($node/@type,"right")) then $node!((plan:optional|plan:negation-expr)/plan:*,plan:expr/plan:*)
      else $node!(plan:expr/plan:*,(plan:optional|plan:negation-expr)/plan:*)
    )
    default return $node/*[not(local-name(.) = ("hash","scatter"))]
  let $lhs := $subs[1]
  let $lhsID := $id || "_L"
  let $rhs := $subs[2]
  let $rhsID := $id || "_R"
  return (
    let $maps := makeGraph($lhs,$lhsID)
    return (
      head($maps)=>map:with("_parent",$id)=>map:with("_parentLabel","left"),
      tail($maps)
    ),
    let $maps := makeGraph($rhs,$rhsID)
    return (
      head($maps)=>map:with("_parent",$id)=>map:with("_parentLabel","right"),
      tail($maps)
    )
  )
};

declare function makeGenericGraph($node as element(), $id as xs:string)
{
  map:map()
  =>map:with("_id",$id)
  =>nameAndAttrs($node),

  for $c at $pos in $node/*
  let $newID := concat($id, "_", $pos)
  return (
    let $maps := makeGraph($c,$newID)
    return (
      head($maps)=>map:with("_parent",$id),
      tail($maps)
    )
  )
};

declare function makeGraph($node as element(), $id as xs:string)
{
  switch(true())
  case exists($node/self::plan:join-filter) return makeJoinFilter($node,$id)
  case contains(local-name($node),"join") and local-name($node)!="star-join" return makeJoinGraph($node,$id)
  case exists($node/self::plan:project) return makeProjectGraph($node,$id)
  case exists($node/self::plan:order-by) return makeOrderGraph($node,$id)
  case exists($node/self::plan:triple-index) return makeTripleGraph($node,$id)
  case exists($node/self::plan:template-view) return makeTemplateViewGraph($node,$id)
  case exists($node/self::plan:literal) return makeLiteralGraph($node,$id)
  case exists($node/self::plan:plan) return makeGraph($node/plan:*[1],$id)
  default return makeGenericGraph($node,$id)
};

declare function makeHTML($in as element())
{
  let $out := makeGraph($in, "N")
  return
    <html>
      <head>
        <script type="text/javascript" src="xtrace/lib/d3/d3.v3.min.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/lib/jQuery/jquery-1.9.0.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/lib/jQuery/jquery.tipsy.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/lib/dagre/dagre.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/js/Minimap.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/js/MinimapZoom.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/js/DirectedAcyclicGraph.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/js/Graph.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/js/Tooltip.js"><!-- --></script>
        <script type="text/javascript" src="xtrace/js/qp.js"><!-- --></script>
        <link href="xtrace/stylesheets/xtrace.css" rel="stylesheet" type="text/css" />
        <link href="xtrace/stylesheets/tipsy.css" rel="stylesheet" type="text/css" />
        <link href="xtrace/stylesheets/jquery.contextMenu.css" rel="stylesheet" type="text/css" />
        <script>
          input = { xdmp:quote(json:to-array($out)) };

          window.onload = function() {{
            var params = getParameters();
            window.qp = new QueryPlan(document.body,input,params);
          }}
        </script>
      </head>
      <body width="100%" height="100%" style="margin: 0"></body>
    </html>
};