// Copyright (c) 2012, 杨博 (Yang Bo)
// All rights reserved.
//
// Author: 杨博 (Yang Bo) <pop.atry@gmail.com>
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name of the <ORGANIZATION> nor the names of its contributors
//   may be used to endorse or promote products derived from this software
//   without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

package com.dongxiguo.continuation;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr;
#end
using Lambda;

/**
  @author 杨博 <pop.atry@gmail.com>
**/
@:final
class Continuation
{
  /** Helper for making a block of code that uses @await, when you don't care
   *  about when block of code finishes. This is analogous to spawning a thread.
   *
   *  Example:
   *
   *  Continuation.doAsync({
   *    @await fun1();
   *    @await fun2();
   *    trace("executed later");
   *  });
   *  trace("executed immediately");
   */
  macro public static function doAsync(expr:Expr):Expr {
    return macro com.dongxiguo.continuation.Continuation.cpsFunction(function() {
      $expr;
    })(function(){});
  }
  
  /**
    Wrap a function to CPS function.

    In wrapped function, you can use <code>@await</code> prefix to invoke other asynchronous functions.
   **/
  #if haxe3
  macro public static function cpsFunction(expr:Expr):Expr
  #else
  @:macro public static function cpsFunction(expr:Expr):Expr
  #end
  {
    switch (expr.expr)
    {
      case EFunction(name, f):
      {
        var originExpr = f.expr;
        return
        {
          pos: expr.pos,
          expr: EFunction(
            name,
            {
              ret: TPath(
                {
                  sub: null,
                  params: [],
                  pack: [],
                  name: "Void"
                }),
              params: f.params,
              args: f.args.concat(
                [
                  {
                    name: "__return",
                    opt: false,
                    value: null,
                    type: f.ret == null ? null : TFunction(
                      [ f.ret ],
                      TPath(
                        {
                          sub: null,
                          params: [],
                          pack: [],
                          name: "Void"
                        }))
                  }
                ]),
              expr: ContinuationDetail.transform(
                originExpr,
                0,
                false,
                function(transformed)
                {
                  transformed.push(
                  {
                    expr: ECall(macro __return, []),
                    pos: originExpr.pos,
                  });
                  return
                  {
                    pos: originExpr.pos,
                    expr: EBlock(transformed),
                  }
                })
            })
        };
      }
      default:
      {
        throw "CPS.cpsFunction expect a function as parameter.";
      }
    }
  }


  /**
    When you add <code>@:build(com.dongxiguo.continuation.Continuation.cpsByMeta("metaName"))</code> in front of a class, any method with same metadata name from <code>metaName</code> in that class will be transfromed to CPS function.

    In these methods, you can use <code>@await</code> prefix to invoke other asynchronous functions.
  **/
  #if haxe3
  @:noUsing macro public static function cpsByMeta(metaName:String):Array<Field>
  #else
  @:noUsing @:macro public static function cpsByMeta(metaName:String):Array<Field>
  #end
  {
    return cpsByMetaFields(metaName, Context.getBuildFields());
  }

  #if macro
  public static function cpsByMetaFields(metaName:String, bf:Array<Field>) : Array<Field> 
  {
    for (field in bf)
    {
      switch (field.kind)
      {
        case FFun(f):
        {
          var originReturnType = f.ret;
          for (m in field.meta)
          {
            if (m.name == metaName)
            {
              f.args = f.args.concat(
                [
                  {
                    name: "__return",
                    opt: false,
                    value: null,
                    type: originReturnType == null ? null : TFunction(
                      [ originReturnType ],
                      TPath(
                        {
                          sub: null,
                          params: [],
                          pack: [],
                          name: "Void"
                        }))
                  }
                ]);
              f.ret = TPath(
                {
                  sub: null,
                  params: [],
                  pack: [],
                  name: "Void"
                });
              var originExpr = f.expr;
              if ( originExpr != null ) {
                f.expr = ContinuationDetail.transform(
                  originExpr,
                  0,
                  false,
                  function(transformed)
                  {
                    transformed.push(
                    {
                      expr: ECall(macro __return, []),
                      pos: originExpr.pos,
                    });
                    return
                    {
                      pos: originExpr.pos,
                      expr: EBlock(transformed),
                    }
                  });
              }
              break;
            }
          }
        }
        default:
        {
          continue;
        }
      }
    }
    return bf;
  }
  #end
}

/**
  For internal use only. Don't access it immediately.
  @private
**/
@:final
class ContinuationDetail
{
  #if macro
  static var seed:Int = 0;

  static function unpack(exprs: Array<Expr>, pos: Position):Expr
  {
    if (exprs.length != 1)
    {
      Context.error("Expect one return value, but there are " + exprs.length +
      " return values.", pos);
    }
    return exprs[0];
  }

  static inline function transformCondition(
    pos:Position,
    inAsyncLoop:Bool,
    econd:Expr,
    eif:Expr,
    eelse:Null<Expr>, rest:Array<Expr>->Expr):Expr
  {
    return transform(
      econd,
      0,
      inAsyncLoop,
      function(econdResult)
      {
        return
        {
          pos: pos,
          expr: EIf(
            unpack(econdResult, econd.pos),
            transform(eif, 0, inAsyncLoop, rest),
            eelse == null ? rest([]) : transform(eelse, 0, inAsyncLoop, rest)),
        };
      });
  }

  static var stackProtect = 0;
  static inline var MAX_STACK = 50;
  public static inline function transform(origin:Expr, maxOutputs:Int, inAsyncLoop:Bool, rest:Array<Expr>->Expr) : Expr
  {
    ++stackProtect;
    var out;
    if ( stackProtect > MAX_STACK ) {
      out = delay(origin.pos, function() return transform(origin, maxOutputs, inAsyncLoop, rest));
    } else {
      out = requiresTransform(inAsyncLoop, origin)
        ? transform_(origin, maxOutputs, inAsyncLoop, rest)
        : rest([origin]);
    }
    --stackProtect;
    return out;
  }

  static function transform_(origin:Expr, maxOutputs:Int, inAsyncLoop:Bool, rest:Array<Expr>->Expr) : Expr {
    switch (origin.expr)
    {
      // @fork(identifier in iterable) { ... forked code ... }
      case EMeta({name:"fork", params:[{expr:EIn({expr:EConst(CIdent(ident)), pos:_}, it), pos:_}]}, forkExpr):
        var fork = macro {
          var $ident, __join = @await com.dongxiguo.continuation.utils.ForkJoin.fork($it);
          $forkExpr; 
          @await __join();
        };
        return transform(fork, maxOutputs, inAsyncLoop, rest);
      case EMeta({name:"await", params:[], pos:_}, {expr:ECall(e, originParams), pos:_}):
      {
        return transformAsync(e, maxOutputs, inAsyncLoop, origin.pos, originParams, rest);
      }
      case EMeta(_, _):
      {
        return rest([origin]);
      }
      case EWhile(econd, e, normalWhile):
      {
        // If there are no asynchronous calls in this loop, then we only need to replace return statements.
        if ( !requiresTransform(inAsyncLoop, econd) && !hasAsyncCall(e) ) {
          return rest([{expr:EWhile(econd, replaceFlowControl(e, false), normalWhile), pos:origin.pos}]);
        }

        var continueName = "__continue_" + seed++;
        var continueIdent =
        {
          pos: origin.pos,
          expr: EConst(CIdent(continueName))
        };
        var breakName =
          "__break_" + seed++;
        var breakIdent =
        {
          pos: origin.pos,
          expr: EConst(CIdent(breakName))
        };
        var doBody = transform(e, 0, true,
          function(eResult)
          {
            return
            {
              pos: origin.pos,
              expr: EBlock(eResult.concat([ macro $continueIdent()]))
            };
          });
        var doExpr = macro 
        {
          inline function __break()
          {
            $breakIdent();
          }
          inline function __continue()
          {
            $continueIdent();
          }
          $doBody;
        };
        var continueBody = transform(
          econd, 0, inAsyncLoop,
          function(econdResult)
          {
            return
            {
              pos: origin.pos,
              expr: EIf(
                unpack(econdResult, econd.pos),
                doExpr,
                macro $breakIdent())
            };
          });
        var breakBody = rest([]);
        var start = normalWhile ? macro $continueIdent() : doBody;
        return macro
        {
          function $breakName():Void
          {
            $breakBody;
          }
          var $continueName = null;
          $continueIdent = function():Void
          {
            $continueBody;
          }
          $start;
        };
      }
      case EVars(originVars):
      {
        function transformNext(i:Int, lastI:Int, values:Array<Null<Expr>>):Expr
        {
          if (i == originVars.length)
          {
            var newVars = [];
            for (i in 0...originVars.length)
            {
              var valueExpr = i < values.length ? values[i] : null;
              var originVar = originVars[i];
              newVars.push({ type: originVar.type, name: originVar.name, expr: valueExpr, });
            }
            var varExpr = {
              pos: origin.pos,
              expr: EVars(newVars),
            };
            var restExpr = rest([]);
            return macro { $varExpr; $restExpr; }
          }
          else
          {
            var originVar = originVars[i];
            if (originVar.expr == null)
            {
              return transformNext(i + 1, lastI, values);
            }
            else
            {
              return transform(originVar.expr, (i-lastI)+1, inAsyncLoop, function(varResult)
              {
                var v = values.concat([]);
                if (i + 1 < varResult.length)
                {
                  return Context.error(
                    "Expect " + varResult.length + " variable declarations.",
                    origin.pos);
                }
                for (j in 0...varResult.length)
                {
                  var slot = j + i + 1 - varResult.length;
                  if (v[slot] == null)
                  {
                    v[slot] = varResult[j];
                  }
                  else
                  {
                    return Context.error(
                      "Expect " + varResult.length + " variable declarations.",
                      origin.pos);
                  }
                }
                return transformNext(i + 1, i + 1, v);
              });
            }
          }
        }
        return transformNext(0, 0, []);
      }
      case EUntyped(e):
      {
        return transform(
          e, 0, inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: EUntyped(unpack(eResult, origin.pos))
                }
              ]);
          });
      }
      case EUnop(op, postFix, e):
      {
        return transform(
          e, 1, inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: EUnop(op, postFix, unpack(eResult, origin.pos))
                }
              ]);
          });
      }
      #if !haxe3
      case EType(e, field):
      {
        return transform(
          e, 0, inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: EType(unpack(eResult, origin.pos), field)
                }
              ]);
          });
      }
      #end
      case ETry(e, catches):
      {
        var endTryName = "__endTry_" + seed++;
        var endTryIdent =
        {
          pos: origin.pos,
          expr: EConst(CIdent(endTryName))
        }
        var isVoidTry = switch (Context.follow(Context.typeof(e)))
        {
          #if (haxe_211 || haxe3)
          case TAbstract(t, _):
          #else
          case TInst(t, params):
          if (params.length != 0) { false; } else
          #end
          {
            var voidType = t.get();
            voidType.module == "StdTypes" && voidType.name == "Void";
          }
          default: false;
        }
        var tryResultName = "__tryResult_" + seed++;
        var tryResultIdent =
        {
          pos: origin.pos,
          expr: EConst(CIdent(tryResultName))
        }
        var endTryFunction =
        {
          pos: origin.pos,
          expr: EFunction(
            endTryName,
            {
              ret: null,
              params: [],
              expr: rest(isVoidTry ? [] : [ tryResultIdent ]),
              args: isVoidTry ? [] :
              [
                {
                  name: tryResultName,
                  opt: true,
                  type: null,
                  value: null
                }
              ]
            })
        }
        var tryBody = isVoidTry ? (macro { $e; __noException = true; }) : (macro { $tryResultIdent = $e; __noException = true; });
        var transformedTry =
        {
          pos: origin.pos,
          expr: ETry(tryBody, catches.map(
            function(catchBody)
            {
              return
              {
                expr: transform(
                  catchBody.expr,
                  0, inAsyncLoop,
                  function(catchResult)
                  {
                    switch (catchResult.length)
                    {
                      case 1:
                      {
                        return
                        {
                          pos: catchBody.expr.pos,
                          expr: ECall(
                            endTryIdent, isVoidTry ? [] :
                            [
                              {
                                pos: catchBody.expr.pos,
                                expr: ECast(
                                  unpack(catchResult, catchBody.expr.pos),
                                  null)
                              }
                            ])
                        };
                      }
                      default:
                      {
                        return
                        {
                          pos: origin.pos,
                          expr: ECall(endTryIdent, catchResult)
                        };
                      }
                    }
                  }),
                type: catchBody.type,
                name: catchBody.name
              }
            }
          ).array())
        }
        return
          isVoidTry ?
          macro
          {
            $endTryFunction;
            var __noException = false;
            $transformedTry;
            if (__noException)
            {
              $endTryIdent();
            }
          } :
          macro
          {
            $endTryFunction;
            var __noException = false;
            var $tryResultName = cast null;
            $transformedTry;
            if (__noException)
            {
              $endTryIdent($tryResultIdent);
            }
          };
      }
      case EThrow(e):
      {
        return transform(
          e,
          1,
          inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: EThrow(unpack(eResult, origin.pos))
                }
              ]);
          });
      }
      case ETernary(econd, eif, eelse):
      {
        return transformCondition(origin.pos, inAsyncLoop, econd, eif, eelse, rest);
      }
      case ESwitch(e, cases, edef):
      {
        return transform(e, 1, inAsyncLoop, function(eResult) : Expr
        {
          var transformedCases = [];
          for ( c in cases ) {
            if (c.expr == null) {
              transformedCases.push({ expr: rest([]), guard: c.guard, values: c.values });
            } else {
              transformedCases.push({ expr: transform(c.expr, 0, inAsyncLoop, rest), guard: c.guard, values: c.values });
            }
          }

          var transformedDefault;
          if ( edef == null ) {
            transformedDefault = null;
          } else if ( edef.expr == null ) {
            transformedDefault = rest([]);
          } else {
            transformedDefault = transform(edef, 0, inAsyncLoop, rest);
          }

          return {
            pos: origin.pos,
            expr: ESwitch(unpack(eResult, e.pos), transformedCases, transformedDefault),
          };
        });
      }
      case EReturn(returnExpr):
      {
        if (returnExpr == null)
        {
          return
          {
            pos: origin.pos,
            expr: ECall(
              {
                pos: origin.pos,
                expr: EConst(CIdent("__return"))
              },
              [])
          };
        }
        switch (returnExpr.expr)
        {
          case EMeta({name:"await", params:[], pos:_}, {expr:ECall(e, originParams), pos:_}):
            // Optimization: pass continuation 
            function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
            {
              if (i == originParams.length)
              {
                return transform(e, 1, inAsyncLoop, function(functionResult)
                {
                  transformedParameters.push(
                  {
                    expr: EConst(CIdent("__return")),
                    pos: origin.pos
                  });
                  return
                  {
                    pos: origin.pos,
                    expr: ECall(
                      unpack(functionResult, origin.pos),
                      transformedParameters),
                  };
                });
              }
              else
              {
                return transform(
                  originParams[i],
                  1,
                  inAsyncLoop,
                  function(parameterResult:Array<Expr>):Expr
                  {
                    for (e in parameterResult)
                    {
                      transformedParameters.push(e);
                    }
                    return transformNext(i + 1, transformedParameters);
                  });
              }
            }
            return transformNext(0, []);
          case _:
        }
        return transform(
          returnExpr,
          1,
          inAsyncLoop,
          function(eResult)
          {
            return
            {
              pos: origin.pos,
              expr: ECall(
                {
                  pos: origin.pos,
                  expr: EConst(CIdent("__return"))
                },
                eResult)
            };
          });
      }
      case EParenthesis(e):
      {
        return transform(e, maxOutputs, inAsyncLoop, rest);
      }
      case EObjectDecl(originFields):
      {
        function transformNext(i:Int, transformedFields:Array<{ field : String, expr : Expr }>):Expr
        {
          if (i == originFields.length)
          {
            return rest(
            [
              {
                pos: origin.pos,
                expr: EObjectDecl(transformedFields),
              }
            ]);
          }
          else
          {
            var originField = originFields[i];
            return transform(
              originField.expr,
              1,
              inAsyncLoop,
              function(valueResult:Array<Expr>):Expr
              {
                for (e in valueResult)
                {
                  transformedFields.push(
                    {
                      field: originField.field,
                      expr: unpack(valueResult, originField.expr.pos),
                    });
                }
                return transformNext(i + 1, transformedFields);
              });
          }
        }
        return transformNext(0, []);
      }
      case ENew(t, originParams):
      {
        function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
        {
          if (i == originParams.length)
          {
            return rest(
            [
              {
                pos: origin.pos,
                expr: ENew(
                  t,
                  transformedParameters),
              }
            ]);
          }
          else
          {
            return transform(
              originParams[i],
              1,
              inAsyncLoop,
              function(parameterResult:Array<Expr>):Expr
              {
                for (e in parameterResult)
                {
                  transformedParameters.push(e);
                }
                return transformNext(i + 1, transformedParameters);
              });
          }
        }
        return transformNext(0, []);
      }
      case EIn(_, _):
      {
        // Unsupported. Don't change it.
        return rest([origin]);
      }
      case EIf(econd, eif, eelse):
      {
        return transformCondition(origin.pos, inAsyncLoop, econd, eif, eelse, rest);
      }
      case EFunction(_, _):
      {
        return rest([origin]);
      }
      case EFor(it, expr):
      {
        // If there are no asynchronous calls in this loop, then we only need to replace return statements.
        if ( !hasAsyncCall(expr) ) {
          return rest([{expr:EFor(it, replaceFlowControl(expr, false)), pos:origin.pos}]);
        }

        switch (it.expr)
        {
          case EIn(e1, e2):
          {
            var elementName =
              switch (e1.expr)
              {
                case EConst(CIdent(s)): s;
                case _: Context.error("Expect identify before \"in\".", e1.pos);
              };
            return transform(
              macro
              {
                var __iterator = null;
                {
                  inline function setIterator<T>(
                    iterable:Iterable<T> = null,
                    iterator:Iterator<T> = null):Void
                  {
                    __iterator = iterable != null ? iterable.iterator() : iterator;
                  }
                  setIterator($e2);
                }
                while (__iterator.hasNext())
                {
                  var $elementName = __iterator.next();
                  $expr;
                }
              },
              0,
              true,
              rest);
          }
          default:
          {
            Context.error("Expect \"in\" in \"for\".", it.pos);
            return null;
          }
        }
      }
      case EField(e, field):
      {
        return transform(
          e,
          1,
          inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: EField(unpack(eResult, origin.pos), field)
                }
              ]);
          });
      }
      case EDisplayNew(_):
      {
        return rest([origin]);
      }
      case EDisplay(_, _):
      {
        return rest([origin]);
      }
      case EContinue:
      {
        return macro __continue();
      }
      case EConst(_):
      {
        return rest([origin]);
      }
      case ECheckType(e, t):
      {
        return transform(
          e,
          1,
          inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: ECheckType(unpack(eResult, e.pos), t)
                }
              ]);
          });
      }
      case ECast(e, t):
      {
        return transform(
          e,
          1,
          inAsyncLoop,
          function(eResult)
          {
            return rest(
              [
                {
                  pos: origin.pos,
                  expr: ECast(unpack(eResult, e.pos), t)
                }
              ]);
          });
      }
      case ECall(e, originParams):
      {
        function finalTransform(transformedParameters:Array<Expr>) {
          return transform(e, 1, inAsyncLoop, function(functionResult)
          {
            return rest([
            {
              pos: origin.pos,
              expr: ECall(
                unpack(functionResult, origin.pos),
                transformedParameters),
            }]);
          });
        }

        // skip recursion if we don't need it.
        if ( !originParams.exists(requiresTransform.bind(inAsyncLoop)) ) {
          return finalTransform(originParams.copy());
        }

        function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
        {
          if (i == originParams.length)
          {
            return finalTransform(transformedParameters);
          }
          else
          {
            return transform(
              originParams[i],
              1,
              inAsyncLoop,
              function(parameterResult:Array<Expr>):Expr
              {
                for (e in parameterResult)
                {
                  transformedParameters.push(e);
                }
                return transformNext(i + 1, transformedParameters);
              });
          }
        }
        return transformNext(0, []);
      }
      case EBreak:
      {
        return macro __break();
      }
      case EBlock(exprs):
      {
        function transformNext(i:Int):Expr
        {
          if (i == exprs.length - 1)
          {
            return transform(exprs[i], 0, inAsyncLoop, rest);
          }
          else
          {
            return transform(exprs[i], 0, inAsyncLoop,
              function(transformedLine:Array<Expr>)
              {
                // In order to avoid excessive recursion, we eat up all of the non-async lines.
                var next = i+1;
                while ( next < exprs.length-1 ) {
                  if ( !requiresTransform(inAsyncLoop, exprs[next]) ) {
                    transformedLine.push(exprs[next++]); 
                  } else {
                    break;
                  }
                }
                transformedLine.push(transformNext(next));
                return
                {
                  pos: origin.pos,
                  expr: EBlock(transformedLine),
                }
              }
            );
          }
        }
        return transformNext(0);
      }
      case EBinop(op, e1, e2):
      {
        return transform(
          e1,
          0,
          inAsyncLoop,
          function(e1Result)
          {
            return transform(e2, 1, inAsyncLoop, function(e2Result)
            {
              return rest(
                [
                  {
                    pos: origin.pos,
                    expr: EBinop(
                      op,
                      unpack(e1Result, e1.pos),
                      unpack(e2Result, e2.pos))
                  }
                ]);
            });
          });
      }
      case EArrayDecl(originParams):
      {
        function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
        {
          if (i == originParams.length)
          {
            return rest(
            [
              {
                pos: origin.pos,
                expr: EArrayDecl(transformedParameters),
              }
            ]);
          }
          else
          {
            return transform(
              originParams[i],
              1,
              inAsyncLoop,
              function(parameterResult:Array<Expr>):Expr
              {
                for (e in parameterResult)
                {
                  transformedParameters.push(e);
                }
                return transformNext(i + 1, transformedParameters);
              });
          }
        }
        return transformNext(0, []);
      }
      case EArray(e1, e2):
      {
        return transform(
          e1,
          1,
          inAsyncLoop,
          function(e1Result)
          {
            return transform(e2, 1, inAsyncLoop, function(e2Result)
            {
              return rest(
                [
                  {
                    pos: origin.pos,
                    expr: EArray(
                      unpack(e1Result, e1.pos),
                      unpack(e2Result, e2.pos))
                  }
                ]);
            });
          });
      }
    }
  }

  static function replaceFlowControl( expr:Expr, inAsyncLoop:Bool ) : Expr {
    function f(e:Expr) {
      if ( e == null ) return null;
      if ( e.expr == null ) return e;
      switch ( e.expr ) {
      case EReturn(returnExpr):
        if (returnExpr == null) {
          return { pos: e.pos, expr:EBlock([
            {
              pos: e.pos,
              expr: ECall({pos: e.pos, expr: EConst(CIdent("__return"))}, []),
            },
            {
              pos: e.pos,
              expr : EReturn(null)
            }
          ])};
        } else {
          return transform(
            returnExpr,
            1,
            false,
            function(eResult) {
              return { pos: e.pos, expr:EBlock([
                {
                  pos: e.pos,
                  expr: ECall({pos: e.pos, expr: EConst(CIdent("__return"))}, eResult)
                },
                {
                  pos: e.pos,
                  expr : EReturn(null)
                }
              ])};
            }
          );
        }
      case EContinue if (inAsyncLoop): return macro { __continue(); return; }
      case EBreak if (inAsyncLoop): return macro { __break(); return; }
      case EFunction(_,_): return e;
      case _: return haxe.macro.ExprTools.map(e, f);
      }
    }
    return f(expr);
  }

  static function hasAsyncCall( expr : Expr ) : Bool {
    var found = false; 
    function f(e:Expr) {
      if ( e != null && e.expr != null ) {
        switch ( e.expr ) {
        case EMeta({name:"await", params:[], pos:_}, {expr:ECall(_, _), pos:_}): found = true;
        case EFunction(_,_):
        case _: haxe.macro.ExprTools.iter(e, f);
        }
      }
    }
    f(expr);
    return found;
  }

  static function requiresTransform( inAsyncLoop:Bool, expr : Expr ) : Bool {
    if ( expr == null ) return false;
    var found = false; 
    var stack = [expr];
    while ( stack.length > 0 ) {
      var e = stack.pop();
      switch ( e.expr ) {
      case EMeta({name:"await", params:[], pos:_}, {expr:ECall(_, _), pos:_}): found = true;
      case EReturn(_): found = true;
      case EBreak, EContinue: if ( inAsyncLoop ) found = true;
      case EFunction(_,_):
      case _: haxe.macro.ExprTools.iter(e, stack.push);
      }
    }
    return found;
  }

  static inline function transformAsync(e:Expr, numArgs:Int, inAsyncLoop:Bool, pos:Position, originParams:Array<Expr>, rest:Array<Expr>->Expr) : Expr {
    inline function transformFinal(transformedParameters:Array<Expr>) {
      return transform(e, 0, inAsyncLoop, function(functionResult) {
        var completion = function(defs, results) {
          transformedParameters.push(
          {
            pos: pos,
            expr: EFunction(null,
            {
              ret: null,
              params: [],
              expr: rest(results),
              args: defs
            })
          });
          return
          {
            pos: pos,
            expr: ECall(
              unpack(functionResult, pos),
              transformedParameters),
          };
        };

        if ( numArgs == 0 ) {
          // See if we're calling our super class
          // This avoids Haxe complaining about creating a closure on super
          var exprToType = unpack(functionResult, pos);
          switch ( exprToType.expr ) {
          case EField({expr:EConst(CIdent("super")), pos:_}, fnName):
            exprToType = macro this.$fnName;
          case _:
          }

          // Number of outputs wasn't specified, need to inspect the caller.
          // We have to delay here, because the type of the expression may not be valid until the code generation 
          // has unrolled.
          // Delaying also ensures that we do not exceed the stack size of the macro processor, due to recursive
          // invocation of cps macros.
          var solved = null;
          return delay(e.pos, function() {
            var type = Context.follow(Context.typeof(exprToType));
            // protect reentrancy
            if ( solved != null ) {
              return solved;
            }

            var handlerArgResult = [];
            var handlerArgDefs = [];
            switch ( type ) {
            case TFun(args, _):
              switch ( Context.follow(args[args.length-1].t) ) {
              case TFun(handlerArgs, _): 
                numArgs = handlerArgs.length;
                for ( handlerArg in handlerArgs ) {
                  var name = "__parameter_" + seed++;
                  handlerArgResult.push(
                    {
                      pos: pos,
                      expr: EConst(CIdent(name))
                    });
                  handlerArgDefs.push(
                    {
                      opt: handlerArg.opt,
                      name: name,
                      type: null,
                      value: null
                    });
                }
              case _: numArgs = 0;
              }
            case _: Context.error("@await can only be used on a function call", e.pos);
            }
            solved = completion(handlerArgDefs, handlerArgResult);
            return solved;
          });
        } else {
          // Assume the number of outputs is the number of vars we're assigning to.
          // This is typically one, unless the syntax "var x, y = @await foo()" is used.
          var handlerArgResult = [];
          var handlerArgDefs = [];

          for ( i in 0...numArgs )
          {
            var name = "__parameter_" + seed++;
            handlerArgResult.push(
              {
                pos: pos,
                expr: EConst(CIdent(name))
              });
            handlerArgDefs.push(
              {
                opt: false,
                name: name,
                type: null,
                value: null
              });
          }

          return completion(handlerArgDefs, handlerArgResult);
        }
      });
    }

    function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
    {
      if (originParams == null || i == originParams.length)
      {
        return transformFinal(transformedParameters);
      }
      else
      {
        return transform(
          originParams[i],
          1,
          inAsyncLoop,
          function(parameterResult:Array<Expr>):Expr
          {
            transformedParameters.push(unpack(parameterResult, originParams[i].pos));
            return transformNext(i + 1, transformedParameters);
          });
      }
    }

    return ( !originParams.exists(requiresTransform.bind(inAsyncLoop)) ) 
      ? transformFinal(originParams.copy()) : transformNext(0, []);
  }

  static var nextDelayedID = 0;
  static var delayFunctions = new Array<Void->Expr>();

  static function delay(pos:Position, delayedFunction:Void->Expr):Expr
  {
    var id = nextDelayedID++;
    var idExpr = Context.makeExpr(id, Context.currentPos());
    delayFunctions[id] = delayedFunction;
    return
    {
      pos: pos,
      expr: ECall(macro com.dongxiguo.continuation.Continuation.ContinuationDetail.runDelayedFunction, [idExpr]),
    }
  }

  #end

  #if haxe3
  @:noUsing macro public static function runDelayedFunction(id:Int):Expr
  #else
  @:noUsing @:macro public static function runDelayedFunction(id:Int):Expr
  #end
  {
    return delayFunctions[id]();
  }
}
