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
  /**
    Wrap a function to CPS function.

    In wrapped function, you can use <code>.async()</code> postfix to invoke other asynchronous functions.
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

  public static macro function taskFunction(expr:Expr):Expr {
    switch (expr.expr)
    {
      case EFunction(name, f):
      {
        var originExpr = f.expr;
        var voidDef = TPath({
          sub: null,
          params: [],
          pack: [],
          name: "Void"
        });

        var transformed = ContinuationDetail.transform(
          originExpr,
          true,
          function(transformed)
          {
            transformed.push(
            {
              expr: ECall(macro __return, [{expr:EConst(CIdent("null")), pos:originExpr.pos}]),
              pos: originExpr.pos,
            });
            return
            {
              pos: originExpr.pos,
              expr: EBlock(transformed),
            }
          }
        );

        var innerFn = {
          pos: expr.pos,
          expr: EFunction(null, {
            ret: TPath(
              {
                sub: null,
                params: [],
                pack: [],
                name: "Void"
              }),
            params: [],
            args:
              [
                {
                  name: "__return",
                  opt: false,
                  value: null,
                  type: f.ret == null ? null : TFunction([f.ret], voidDef)
                }
              ],
            expr: transformed
          })
        };

        return
        {
          pos: expr.pos,
          expr: EFunction(
            name,
            {
              ret: TPath(
                {
                  sub: null,
                  params: [f.ret == null ? TPType(voidDef) : TPType(f.ret)],
                  pack: ["com", "dongxiguo", "continuation"],
                  name: "Task"
                }),
              params: f.params,
              args: f.args,
              expr: macro {
                var __task = new com.dongxiguo.continuation.Task();
                return __task.run($innerFn);
              }
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

    In these methods, you can use <code>.async()</code> postfix to invoke other asynchronous functions.
  **/
  #if haxe3
  @:noUsing macro public static function cpsByMeta(metaName:String, asTasks:Bool=false):Array<Field>
  #else
  @:noUsing @:macro public static function cpsByMeta(metaName:String, asTasks:Bool=false):Array<Field>
  #end
  {
    var bf = Context.getBuildFields();
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
              f.expr = ContinuationDetail.transform(
                originExpr,
                asTasks,
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

  static function transformCondition(
    pos:Position,
    asTasks:Bool,
    econd:Expr,
    eif:Expr,
    eelse:Null<Expr>, rest:Array<Expr>->Expr):Expr
  {
    return transform(
      econd,
      asTasks,
      function(econdResult)
      {
        return
        {
          pos: pos,
          expr: EIf(
            unpack(econdResult, econd.pos),
            transform(eif, asTasks, rest),
            eelse == null ? rest([]) : transform(eelse, asTasks, rest)),
        };
      });
  }

  public static function transform(origin:Expr, asTask:Bool, rest:Array<Expr>->Expr):Expr
  {
    return delay(
      origin.pos,
      function()
      {
        return transformNoDelay(origin, asTask, rest);
      });
  }

  static function checkTaskParameter(type:haxe.macro.Type, pos:haxe.macro.Position) : Bool {
    switch ( type ) {
    case TFun(_, ret):
      if ( ret == null ) {
        Context.error("Function does not return a Task", pos);
        return false;
      } else {
        return checkTaskParameter(Context.follow(ret), pos);
      }
    case TInst(classType, typeParams):
      var classType = classType.get();
      if ( Context.defined("cs") ) {
        if ( classType.name != "_Task" || classType.pack.join(".") != "com.dongxiguo.continuation" ) {
          Context.error("value is not a Task", pos);
        }
        return true;
      } else {
        if ( classType.name != "Task" || classType.pack.join(".") != "com.dongxiguo.continuation" ) {
          Context.error("value is not a Task", pos);
        }

        var needParam = true;
        if ( typeParams.length != 0 ) {
          switch ( typeParams[0] ) {
          case TAbstract(t,_): if ( t.get().name == "Void" ) needParam = false;
          default:
          }
        }
        return needParam;
      }
    default: Context.error("value is not a Task", pos); return false;
    }
  }

  static function transformNoDelay(origin:Expr, asTask:Bool, rest:Array<Expr>->Expr):Expr
  {
    switch (origin.expr)
    {
      #if (haxe_211 || haxe3)
      case EMeta(_, _):
      {
        return rest([origin]);
      }
      #end
      case EWhile(econd, e, normalWhile):
      {
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
        var doBody = transform(e, asTask,
          function(eResult)
          {
            return
            {
              pos: origin.pos,
              expr: EBlock(eResult.concat([ macro $continueIdent()]))
            };
          });
        var continueBody = transform(
          econd,
          asTask,
          function(econdResult)
          {
            return
            {
              pos: origin.pos,
              expr: EIf(
                unpack(econdResult, econd.pos),
                macro __do(),
                macro $breakIdent())
            };
          });
        var breakBody = rest([]);
        var startIdent = normalWhile ? macro $continueIdent : macro __do;
        return macro
        {
          function $breakName():Void
          {
            $breakBody;
          }
          var $continueName = null;
          inline function __do()
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
          }
          $continueIdent = function():Void
          {
            $continueBody;
          }
          $startIdent();
        };
      }
      case EVars(originVars):
      {
        function transformNext(i:Int, values:Array<Null<Expr>>):Expr
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
              return transformNext(i + 1, values);
            }
            else
            {
              return transform(originVar.expr, asTask, function(varResult)
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
                return transformNext(i + 1, v);
              });
            }
          }
        }
        return transformNext(0, []);
      }
      case EUntyped(e):
      {
        return transform(
          e,
          asTask,
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
          e,
          asTask,
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
          e,
          asTask,
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
                  asTask,
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
          asTask,
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
        return transformCondition(origin.pos, asTask, econd, eif, eelse, rest);
      }
      case ESwitch(e, cases, edef):
      {
        return transform(e, asTask, function(eResult) : Expr
        {
          var transformedCases = cases.map(function(c)
          {
            if (c.expr == null)
            {
              return { expr: rest([]), #if (haxe_211 || haxe3) guard: c.guard, #end values: c.values };
            }
            else
            {
              return { expr: transform(c.expr, asTask, rest), #if (haxe_211 || haxe3) guard: c.guard, #end values: c.values };
            }
          }).array();
          var transformedDef = edef == null ? rest([]) : transform(edef, asTask, rest);
          return
          {
            pos: origin.pos,
            expr: ESwitch(unpack(eResult, e.pos), transformedCases, transformedDef),
          }
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
          case ECall(e, originParams):
          {
            if (originParams.length == 0)
            {
              switch (e.expr)
              {
                case EField(prefixCall, field):
                {
                  if (field == "async")
                  {
                    switch (prefixCall.expr)
                    {
                      case ECall(e, originParams):
                      {
                        // 优化 e 是另一个异步函数的情况
                        function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
                        {
                          if (i == originParams.length)
                          {
                            return transform(e, asTask, function(functionResult)
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
                              asTask,
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
                      default:
                    }
                  }
                }
                default:
              }
            }
          }
          default:
        }
        return transform(
          returnExpr,
          asTask,
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
        return transform(e, asTask, rest);
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
              asTask,
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
              asTask,
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
        return transformCondition(origin.pos, asTask, econd, eif, eelse, rest);
      }
      case EFunction(_, _):
      {
        return rest([origin]);
      }
      case EFor(it, expr):
      {
        switch (it.expr)
        {
          case EIn(e1, e2):
          {
            var elementName =
              switch (e1.expr)
              {
                case EConst(c):
                  switch (c)
                  {
                    case CIdent(s):
                    {
                      s;
                    }
                    default:
                    {
                      Context.error("Expect identify before \"in\".", e1.pos);
                    }
                  }
                default:
                {
                  Context.error("Expect identify before \"in\".", e1.pos);
                }
              }
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
              asTask,
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
          asTask,
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
          asTask,
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
          asTask,
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
        if (originParams.length == 0)
        {
          switch (e.expr)
          {
            case EField(prefixCall, field):
            {
              if (field == "async")
              {
                switch (prefixCall.expr)
                {
                  case ECall(e, originParams):
                  {
                    return transformAsync(e, origin.pos, asTask, originParams, rest);
                  }
                  default:
                  {
                    if ( asTask )
                    {
                      // allow taskVariable.async()
                      switch ( Context.follow(Context.typeof(prefixCall)) )
                      {
                        case TInst(classType, _):
                        {
                          var classType = classType.get();
                          if ( (Context.defined("cs") && classType.name == "_Task" && classType.pack.join(".") == "com.dongxiguo.continuation") ||
                              (!Context.defined("cs") && classType.name == "Task" && classType.pack.join(".") == "com.dongxiguo.continuation") )
                          {
                            return transformAsync(prefixCall, origin.pos, asTask, null, rest);
                          }
                        }
                        default:
                      }
                    }
                  }
                }
              }
            }
            default:
          }
        }
        function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
        {
          if (i == originParams.length)
          {
            return transform(e, asTask, function(functionResult)
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
          else
          {
            return transform(
              originParams[i],
              asTask,
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
        if (exprs.length == 0)
        {
          return rest([]);
        }
        function transformNext(i:Int):Expr
        {
          if (i == exprs.length - 1)
          {
            return transform(exprs[i], asTask, rest);
          }
          else
          {
            return transform(exprs[i], asTask, function(transformedLine)
            {
              transformedLine.push(transformNext(i + 1));
              return
              {
                pos: origin.pos,
                expr: EBlock(transformedLine),
              }
            });
          }
        }
        return transformNext(0);
      }
      case EBinop(op, e1, e2):
      {
        return transform(
          e1,
          asTask,
          function(e1Result)
          {
            return transform(e2, asTask, function(e2Result)
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
              asTask,
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
          asTask,
          function(e1Result)
          {
            return transform(e2, asTask, function(e2Result)
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

  static function transformAsync(e:Expr, pos:Position, asTask:Bool, originParams:Array<Expr>, rest:Array<Expr>->Expr) : Expr {
    function transformNext(i:Int, transformedParameters:Array<Expr>):Expr
    {
      if (originParams == null || i == originParams.length)
      {
        return transform(e, asTask, function(functionResult)
        {
          if ( asTask ) {
            var handlerArgResult = [];
            var handlerArgDefs = [];

            if ( checkTaskParameter(Context.follow(Context.typeof(unpack(functionResult, e.pos))), e.pos) ) {
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
            var call = originParams == null
              ? unpack(functionResult, pos)
              : { pos:pos, expr:ECall(unpack(functionResult, pos), transformedParameters) };
            var result = {
              pos: pos,
              expr: EFunction(null,
              {
                ret: null,
                params: [],
                expr: rest(handlerArgResult),
                args: handlerArgDefs
              })
            };
            return handlerArgDefs.length != 0
              ? macro $call.then(__task, $result)
              : macro $call.then0(__task, $result);
          } else {
            var handlerArgResult = [];
            var handlerArgDefs = [];
            switch (Context.follow(Context.typeof(unpack(functionResult, e.pos))))
            {
              case TFun(args, _):
              {
                switch (args[args.length - 1].t)
                {
                  case TFun(args, _):
                  {
                    for (handlerArg in args)
                    {
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
                  }
                  default:
                  {
                    var name = "__parameter_" + seed++;
                    handlerArgResult.push(
                      {
                        pos: pos,
                        expr: EConst(CIdent(name))
                      });
                    handlerArgDefs.push(
                      {
                        opt: true,
                        name: name,
                        type: null,
                        value: null
                      });
                  }
                }
              }
              default:
              {
                Context.error("First parameter of async() must be a function.", e.pos);
              }
            }

            transformedParameters.push(
            {
              pos: pos,
              expr: EFunction(null,
              {
                ret: null,
                params: [],
                expr: rest(handlerArgResult),
                args: handlerArgDefs
              })
            });
            return
            {
              pos: pos,
              expr: ECall(
                unpack(functionResult, pos),
                transformedParameters),
            };
          }
        });
      }
      else
      {
        return transform(
          originParams[i],
          asTask,
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

  static var nextDelayedId = 0;

  @:isVar
  static var delayFunctions(get_delayFunctions, set_delayFunctions):Array<Void->Expr>;

  static function set_delayFunctions(value:Array<Void->Expr>):Array<Void->Expr>
  {
    return delayFunctions = value;
  }

  static function get_delayFunctions():Array<Void->Expr>
  {
    if (delayFunctions == null)
    {
      Context.onGenerate(
        function(allType)
        {
          delayFunctions = null;
        });
      return delayFunctions = [];
    }
    else
    {
      return delayFunctions;
    }
  }

  static function delay(pos:Position, delayedFunction:Void->Expr):Expr
  {
    var id = delayFunctions.length;
    var idExpr = Context.makeExpr(id, Context.currentPos());
    delayFunctions.push(delayedFunction);
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
