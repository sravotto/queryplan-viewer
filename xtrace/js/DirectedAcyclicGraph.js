function DirectedAcyclicGraph() {
    
    var layout_count = 0;
    var animate = true;
    
    /*
     * Main rendering function
     */
    function graph(selection) {
        selection.each(function(data) {   
            // Select the g element that we draw to, or add it if it doesn't exist
            var svg = d3.select(this).selectAll("svg").data([data]);

            var defs = svg.enter().append("defs");
            defs.append("marker")
		.attr({
		    "id":"arrowMarker",
		    "viewBox":"0 -5 10 10",
		    "refX":10,
		    "refY":0,
		    "markerWidth":4,
		    "markerHeight":4,
		    "orient":"auto"
		})
		.append("path")
		.attr("d", "M0,-5L10,0L0,5")
		.attr("class","arrowHead");
            defs.append("marker")
		.attr({
		    "id":"leftMarker",
		    "viewBox":"0 0 100 100",
		    "refX":6,
		    "refY":0,
		    "markerWidth":100,
		    "markerHeight":100,
		    "orient":0
		})
                .append("text")
                .attr("x",0).attr("y",6)
                .attr("font-size","5px")
                .attr("font-family","Verdana")
                .text("L");
            defs.append("marker")
		.attr({
		    "id":"rightMarker",
		    "viewBox":"0 0 100 100",
		    "refX":-6,
		    "refY":0,
		    "markerWidth":100,
		    "markerHeight":100,
		    "orient":0
		})
                .append("text")
                .attr("x",0).attr("y",6)
                .attr("font-size","5px")
                .attr("font-family","Verdana")
                .text("R");

            svg.enter().append("svg").append("g").attr("class", "graph").classed("animate", animate);
            
            // Size the chart
            svg.attr("width", width.call(this, data));
            svg.attr("height", height.call(this, data));            
            
            // Get the edges and nodes from the data.  Can have user-defined accessors
            var edges = getedges.call(this, data);
            var nodes = getnodes.call(this, data);

            // Get the existing nodes and edges, and recalculate the node size
            var existing_edges = svg.select(".graph").selectAll(".edge").data(edges, edgeid);
            var existing_nodes = svg.select(".graph").selectAll(".node").data(nodes, nodeid);
            
            var removed_edges = existing_edges.exit();
            var removed_nodes = existing_nodes.exit();
            
            var new_edges = existing_edges.enter()
                .insert("path", ":first-child")
                .attr("class", "edge entering")
                .attr("marker-end", "url(#arrowMarker)");
            var new_nodes = existing_nodes.enter().append("g").attr("class", "node entering");
            
            // Draw new nodes
            new_nodes.each(drawnode);
            existing_nodes.each(sizenode);
            removed_nodes.each(removenode);
            if (animate) {
                removed_edges.classed("visible", false).transition().duration(500).remove();
            } else {
                removed_edges.classed("visible", false).remove();
            }
            
            // Do the layout
            existing_nodes.classed("pre-existing", true);
            layout.call(svg.select(".graph").node(), nodes, edges);
            existing_nodes.classed("pre-existing", false);
            
            // Animate into new positions
            if (animate) {
                svg.select(".graph").selectAll(".edge.visible").transition().duration(800).attrTween("d", graph.edgeTween);//attr("d", graph.splineGenerator);
                existing_nodes.transition().duration(800).attr("transform", graph.nodeTranslate);
            } else {
                svg.select(".graph").selectAll(".edge.visible").attr("d", graph.splineGenerator);      
                existing_nodes.attr("transform", graph.nodeTranslate);         
            }
            
            new_nodes.each(newnodetransition);
            new_edges.attr("d", graph.splineGenerator).classed("visible", true);
            new_edges.each(function(d) {
                if(d.target.report["_parentLabel"] == "left") {
                    d3.select(this).attr("marker-start", "url(#leftMarker)");
                }
                else if(d.target.report["_parentLabel"] == "right") {
                    d3.select(this).attr("marker-start", "url(#rightMarker)");
                }
            });
            existing_nodes.classed("visible", true);
            window.setTimeout(function() {
                new_edges.classed("entering", false);
                new_nodes.classed("entering", false);
            }, 2000);
        });
        
    }


    /*
     * Settable variables and functions
     */
    var width = d3.functor("100%");
    var height = d3.functor("100%");
    var edgeid = function(d) { return d.source.id + "-" + d.target.id; }
    var nodeid = function(d) { return d.id; }
    var nodename = function(d) { return d.report["_name"]; }
    var getnodes = function(d) { return d.getVisibleNodes(); }
    var getedges = function(d) { return d.getVisibleLinks(); }
    var bbox = function(d) {
        return d3.select(this).select("rect").node().getBBox();
    }
    var drawnode = function(d) {
        var formatKeyValue = function(key, value, text) {
            var tspan = text.append("tspan").attr("x", 0).attr("dy", "1.2em");
            tspan.append("tspan").attr("x",0).attr("style","font-weight: bold").text(key + ": ");
            tspan.append("tspan").attr("dx",0).text(value);
        };

        // Attach the DOM elements
        var rect = d3.select(this).append("rect");
        if(d.report["_name"] == "literal") {
            rect.classed("literal",true);
        }
        var text = d3.select(this).append("text").attr("x", 0).attr("text-anchor", "middle");
        text.append("tspan").attr("x", 0).attr("dy", "1em").text(nodename);
        if(d.report.hasOwnProperty("condition")) {
            formatKeyValue("condition",d.report.condition,text);
        }
        if(d.report.hasOwnProperty("value")) {
            formatKeyValue("value",d.report.value,text);
        }
        if(d.report["_name"] == "template-view") {
            formatKeyValue("iri",d.report.iri,text);
        }

        var valFormat = function(val) {
            if(val.hasOwnProperty("column-index")) {
                if(val.hasOwnProperty("name")) {
                    return val["column-index"] + " (" + val.name + ")";
                } else {
                    var result = val["column-index"] + " (";
                    if(val.view !== undefined) {
                        if(val.schema !== undefined)
                            result += val.schema + ".";
                        result += val.view + ".";
                    }
                    result += val.column + ")";
                    return result;
                }
            }
            else if(val.type == "global-variable") {
                return val.name + " (global)";
            }
            return val.value;
        };

        if(d.report.hasOwnProperty("column") && Array.isArray(d.report.column)) {
            for(var i=0; i<d.report.column.length; ++i) {
                var val = d.report.column[i];
                var format = valFormat(val);
                if(val.nullable == true) format += " [nullable]";
                formatKeyValue("column",format,text);
            }
        }
        var gnProps = ["subject","predicate","object","graph","row","fragment","content"];
	for(var i = 0; i < gnProps.length; i++) {
	    var key = gnProps[i];
            if(d.report.hasOwnProperty(key)) {
                var val = d.report[key];
                formatKeyValue(key,valFormat(val),text);
            }
        }

        var prior_pos = nodepos.call(this, d);
        if (prior_pos!=null) {
            d3.select(this).attr("transform", graph.nodeTranslate);
        }
    }    
    var sizenode = function(d) {
        // Because of SVG weirdness, call sizenode as necessary to ensure a node's size is correct
        var lines = 0;
        var maxWidth = 190;
        d3.select(this).selectAll("text > tspan").each(function(d) {
            var textWidth = d3.select(this).node().getComputedTextLength();
            if(maxWidth<textWidth) maxWidth = textWidth;
            ++lines;
        });
        var node_bbox = {"height": 20*lines + 10, "width": maxWidth + 10};
        var rect = d3.select(this).select('rect'), text = d3.select(this).select('text');
        var text_bbox = {"height": 20*lines, "width": maxWidth};
        rect.attr("x", -node_bbox.width/2).attr("y", -node_bbox.height/2)
        rect.attr("width", node_bbox.width).attr("height", node_bbox.height);
        text.attr("x", -text_bbox.width/2).attr("y", -text_bbox.height/2);
    }
    var removenode = function(d) {
        if (animate) {
            d3.select(this).classed("visible", false).transition().duration(200).remove();
        } else {
            d3.select(this).classed("visible", false).remove();            
        }
    }
    var newnodetransition = function(d) {
        d3.select(this).classed("visible", true).attr("transform", graph.nodeTranslate);
    }
    var layout = function(nodes_d, edges_d) {
        // Dagre requires the width, height, and bbox of each node to be attached to that node's data
        var start = new Date().getTime();
        d3.select(this).selectAll(".node").each(function(d) {
            d.bbox = bbox.call(this, d);
            d.width = d.bbox.width;
            d.height = d.bbox.height;
            d.dagre_prev = d.dagre_id==layout_count ? d.dagre : null;
            d.dagre_id = layout_count+1;
        });
        layout_count++;
        console.log("layout:bbox", (new Date().getTime() - start));
        
        // Call dagre layout.  Store layout data such that calls to x(), y() and points() will return them
        start = new Date().getTime();
        dagre.layout().nodeSep(20).edgeSep(5).rankSep(20).nodes(nodes_d).edges(edges_d).run(); 
        console.log("layout:dagre", (new Date().getTime() - start));   
        
        // Also we want to make sure that the control points for all the edges overlap the nodes nicely
        d3.select(this).selectAll(".edge").each(function(d) {
            var p = d.dagre.points;
            p.push(dagre.util.intersectRect(d.target.dagre, p.length > 0 ? p[p.length - 1] : d.source.dagre));
            p.splice(0, 0, dagre.util.intersectRect(d.source.dagre, p[0]));
            p[0].y -= 0.5; p[p.length-1].y += 0.5; 
        });
        
        // Try to put the graph as close to previous position as possible
        var count = 0, x = 0, y = 0;
        d3.select(this).selectAll(".node.pre-existing").each(function(d) {
            if (d.dagre_prev) {
                count++;
                x += (d.dagre_prev.x - d.dagre.x);
                y += (d.dagre_prev.y - d.dagre.y);
            }
        });
        if (count > 0) {
            x = x / count;
            y = y / count;
            d3.select(this).selectAll(".node").each(function(d) {
                d.dagre.x += x;
                d.dagre.y += y;
            })
            d3.select(this).selectAll(".edge").each(function(d) {
                d.dagre.points.forEach(function(p) {
                    p.x += x;
                    p.y += y;
                })
            })
        }
    }
    var nodepos = function(d) {
        // Returns the {x, y} location of a node after layout
        return d.dagre;
    }
    var edgepos = function(d) {
        // Returns a list of {x, y} control points of an edge after layout
        return d.dagre.points; 
    }
    
    
    /*
     * A couple of private non-settable functions
     */
    graph.splineGenerator = function(d) {
        return d3.svg.line().x(function(d) { return d.x }).y(function(d) { return d.y }).interpolate("basis")(edgepos.call(this, d));
    }
    
    graph.edgeTween = function(d) {
        var d1 = graph.splineGenerator.call(this, d);
        var path0 = this, path1 = path0.cloneNode();                           
        var n0 = path0.getTotalLength(), n1 = (path1.setAttribute("d", d1), path1).getTotalLength();

        // Uniform sampling of distance based on specified precision.
        var distances = [0], i = 0, dt = Math.max(1/8, 4 / Math.max(n0, n1));
        while ((i += dt) < 1) distances.push(i);
        distances.push(1);

        // Compute point-interpolators at each distance.
        var points = distances.map(function(t) {
            var p0 = path0.getPointAtLength(t * n0),
                p1 = path1.getPointAtLength(t * n1);
            return d3.interpolate([p0.x, p0.y], [p1.x, p1.y]);
        });

        var line = d3.svg.line().interpolate("basis");
        
        return function(t) {
            return line(points.map(function(p) { return p(t); }));
        };
    }
    
    graph.nodeTranslate = function(d) {
        var pos = nodepos.call(this, d);
        return "translate(" + pos.x + "," + pos.y + ")";
    }
    
    function random(min, max) {
        return function() { return min + (Math.random() * (max-min)); }
    }
    
    
    /*
     * Getters and setters for settable variables and function
     */
    graph.width = function(_) { if (!arguments.length) return width; width = d3.functor(_); return graph; }
    graph.height = function(_) { if (!arguments.length) return height; height = d3.functor(_); return graph; }
    graph.edgeid = function(_) { if (!arguments.length) return edgeid; edgeid = _; return graph; }
    graph.nodeid = function(_) { if (!arguments.length) return nodeid; nodeid = _; return graph; }
    graph.nodename = function(_) { if (!arguments.length) return nodename; nodename = _; return graph; }
    graph.nodes = function(_) { if (!arguments.length) return getnodes; getnodes = d3.functor(_); return graph; }
    graph.edges = function(_) { if (!arguments.length) return getedges; getedges = d3.functor(_); return graph; }
    graph.bbox = function(_) { if (!arguments.length) return bbox; bbox = d3.functor(_); return graph; }
    graph.drawnode = function(_) { if (!arguments.length) return drawnode; drawnode = _; return graph; }
    graph.removenode = function(_) { if (!arguments.length) return removenode; removenode = _; return graph; }
    graph.newnodetransition = function(_) { if (!arguments.length) return newnodetransition; newnodetransition = _; return graph; }
    graph.layout = function(_) { if (!arguments.length) return layout; layout = _; return graph; }
    graph.nodepos = function(_) { if (!arguments.length) return nodepos; nodepos = _; return graph; }
    graph.edgepos = function(_) { if (!arguments.length) return edgepos; edgepos = _; return graph; }
    graph.animate = function(_) { if (!arguments.length) return animate; animate = _; return graph; }
    
    return graph;
}