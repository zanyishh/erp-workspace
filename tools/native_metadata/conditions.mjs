// GPL-3.0. Compile a limited expression tree; never execute JavaScript.
import {parseExpression} from '@babel/parser';
const binary=new Set(['==','!=','===','!==','>','<','>=','<=','+','-','*','/']);
const methods=new Set(['includes','indexOf','startsWith','endsWith','toLowerCase','toUpperCase','split','pop']);
function path(n){return n?.type==='Identifier'?n.name:['MemberExpression','OptionalMemberExpression'].includes(n?.type)&&!n.computed?`${path(n.object)}.${n.property.name}`:'';}
function compile(n){
  const environments={'frappe.session.user':'user','frappe.boot.developer_mode':'developer_mode','frappe.boot.versions':'versions'};
  if(environments[path(n)])return {op:'environment',key:environments[path(n)]};
  if(['StringLiteral','NumericLiteral','BooleanLiteral'].includes(n.type))return {op:'literal',value:n.value};
  if(n.type==='NullLiteral'||n.type==='Identifier'&&n.name==='undefined')return {op:'literal',value:null};
  if(n.type==='Identifier'&&['doc','parent'].includes(n.name))return {op:'context',name:n.name};
  if(['MemberExpression','OptionalMemberExpression'].includes(n.type))return {op:'get',object:compile(n.object),key:n.computed?compile(n.property):{op:'literal',value:n.property.name}};
  if(n.type==='ArrayExpression')return {op:'array',values:n.elements.map(compile)};
  if(n.type==='UnaryExpression'&&['!','+','-'].includes(n.operator))return {op:n.operator,args:[compile(n.argument)]};
  if(n.type==='BinaryExpression'&&binary.has(n.operator)||n.type==='LogicalExpression'&&['&&','||','??'].includes(n.operator))return {op:n.operator,args:[compile(n.left),compile(n.right)]};
  if(n.type==='ConditionalExpression')return {op:'?',args:[compile(n.test),compile(n.consequent),compile(n.alternate)]};
  if(n.type==='CallExpression'||n.type==='OptionalCallExpression'){
    if(path(n.callee)==='erpnext.is_perpetual_inventory_enabled' && n.arguments.length===1 && path(n.arguments[0])==='parent.company'){
      return {op:'get',object:{op:'environment',key:'perpetual_inventory'},key:compile(n.arguments[0])};
    }
    if(path(n.callee)==='erpnext.stock.is_subcontracting_or_return_transfer' && n.arguments.length===1 && path(n.arguments[0])==='doc'){
      return compile(parseExpression('doc.purpose == "Send to Subcontractor" || (doc.purpose == "Material Transfer" && doc.is_return)'));
    }
    const method=n.callee.type==='MemberExpression' && !n.callee.computed && n.callee.property.name;
    if(['some','every'].includes(method) && n.arguments.length===1){
      const predicate=n.arguments[0];
      if(predicate.type==='ArrowFunctionExpression' && predicate.params.length===1 && predicate.params[0].type==='Identifier'){
        const negate=predicate.body.type==='UnaryExpression' && predicate.body.operator==='!';
        const field=negate ? predicate.body.argument : predicate.body;
        if(field.type==='MemberExpression' && !field.computed && field.object.type==='Identifier' && field.object.name===predicate.params[0].name){
          return {op:'row_test',method,object:compile(n.callee.object),field:field.property.name,negate};
        }
      }
    }
    if(path(n.callee)==='frappe.datetime.now_date')return {op:'environment',key:'today'};
    if(path(n.callee)==='Boolean'&&n.arguments.length===1)return {op:'!',args:[{op:'!',args:[compile(n.arguments[0])]}]};
    if(n.callee.type==='Identifier'&&['cint','flt','in_list'].includes(n.callee.name))return {op:'call',method:n.callee.name,args:n.arguments.map(compile)};
    if(['MemberExpression','OptionalMemberExpression'].includes(n.callee.type)&&!n.callee.computed&&methods.has(n.callee.property.name))return {op:'method',method:n.callee.property.name,object:compile(n.callee.object),args:n.arguments.map(compile)};
  }
  throw new Error(`Unsupported expression: ${n.type}`);
}
export function compileCondition(expression){
  try{
    if(!expression.startsWith('eval:')){
      if(expression.startsWith('fn:'))throw new Error('A client script is required');
      return {op:'field',name:expression};
    }
    return compile(parseExpression(expression.slice(5).trim().replace(/;+$/,'')));
  }catch{return {op:'unsupported'};}
}
