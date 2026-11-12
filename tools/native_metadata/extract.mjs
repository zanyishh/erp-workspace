// GPL-3.0. Inspect JavaScript syntax only; never execute a source report.
import {parse} from '@babel/parser';

function name(node) {
  if(!node)return '';
  if(node.type==='Identifier')return node.name;
  if(node.type==='StringLiteral')return node.value;
  if(node.type==='MemberExpression'||node.type==='OptionalMemberExpression')return `${name(node.object)}.${name(node.property)}`;
  return '';
}

const unresolved=Symbol('unresolved');
function value(node) {
  if(!node)return unresolved;
  if(['StringLiteral','NumericLiteral','BooleanLiteral'].includes(node.type))return node.value;
  if(node.type==='NullLiteral')return null;
  if(node.type==='ObjectExpression'){
    const result={};
    for(const property of node.properties){
      if(property.type!=='ObjectProperty')return unresolved;
      const parsed=value(property.value);if(parsed===unresolved)return unresolved;
      result[name(property.key)]=parsed;
    }
    return result;
  }
  if(node.type==='TemplateLiteral'&&node.expressions.length===0)return node.quasis[0].value.cooked;
  if(node.type==='UnaryExpression'&&['-','+','!'].includes(node.operator)){
    const operand=value(node.argument);
    if(operand===unresolved)return unresolved;
    return node.operator==='-'?-operand:node.operator==='+'?+operand:!operand;
  }
  if(node.type==='ArrayExpression'){
    const elements=node.elements.map(value);return elements.includes(unresolved)?unresolved:elements;
  }
  if(node.type==='BinaryExpression'&&node.operator==='+'){
    const left=value(node.left),right=value(node.right);
    return left===unresolved||right===unresolved?unresolved:left+right;
  }
  if(node.type==='CallExpression'){
    const callee=name(node.callee),args=node.arguments.map(value);
    if(['__','frappe._'].includes(callee))return args[0];
    if(['frappe.defaults.get_user_default','frappe.defaults.get_default'].includes(callee)&&typeof args[0]==='string')return {native_default:'user',key:args[0]};
    if(['frappe.datetime.get_today','frappe.datetime.now_date'].includes(callee))return {native_default:'today'};
    if(callee==='erpnext.utils.get_fiscal_year')return {native_default:'fiscal_year'};
    if(['frappe.datetime.month_start','frappe.datetime.month_end','frappe.datetime.year_start','frappe.datetime.year_end'].includes(callee))return {native_default:callee.split('.').at(-1)};
    if(['frappe.datetime.add_months','frappe.datetime.add_days'].includes(callee)&&args[0]?.native_default==='today'&&typeof args[1]==='number')return {native_default:'date_offset',unit:callee.endsWith('months')?'months':'days',value:args[1]};
    if(node.callee.type==='MemberExpression'&&name(node.callee.property)==='join'){
      const array=value(node.callee.object);if(Array.isArray(array))return array.join(args[0]??',');
    }
  }
  return unresolved;
}

function walk(node, visit) {
  if(!node||typeof node!=='object')return;
  if(node.type)visit(node);
  for(const [key,entry] of Object.entries(node)){
    if(['loc','comments','leadingComments','trailingComments','innerComments','tokens'].includes(key))continue;
    if(Array.isArray(entry))for(const child of entry)walk(child,visit);
    else if(entry&&typeof entry==='object')walk(entry,visit);
  }
}

export function extractReportFilters(source) {
  const ast=parse(source,{sourceType:'unambiguous',attachComment:false});
  const fields=new Map();const diagnostics=[];let requires_adapter=false;
  const functions=new Map();
  walk(ast,node=>{if(node.type==='FunctionDeclaration')functions.set(name(node.id),node);});
  const resolveArray=(node)=>{
    if(node?.type==='ArrayExpression')return node;
    if(node?.type!=='CallExpression')return null;
    const fn=functions.get(name(node.callee));
    if(!fn)return null;
    const returned=fn.body.body.findLast(s=>s.type==='ReturnStatement')?.argument;
    if(returned?.type==='ArrayExpression')return returned;
    if(returned?.type==='Identifier'){
      for(const statement of fn.body.body){
        if(statement.type!=='VariableDeclaration')continue;
        const variable=statement.declarations.find(d=>name(d.id)===returned.name);
        if(variable?.init?.type==='ArrayExpression')return variable.init;
      }
    }
    return null;
  };
  const readField=(node)=>{
    if(node?.type!=='ObjectExpression'){requires_adapter=true;return;}
    const props=new Map(node.properties.map(p=>[name(p.key),p]));
    const fieldname=value(props.get('fieldname')?.value);
    if(typeof fieldname!=='string')return;
    const field={fieldname};
    for(const key of ['label','fieldtype','options','reqd','hidden','read_only','default','depends_on','mandatory_depends_on','read_only_depends_on']){
      const property=props.get(key);if(!property)continue;
      const parsed=value(property.value);
      if(parsed===unresolved){requires_adapter=true;diagnostics.push(`${fieldname}.${key}`);if(key==='options')field.dynamic_options=true;continue;}
      field[key]=key==='options'&&Array.isArray(parsed)?parsed.map(v=>typeof v==='object'?v.value:v).join('\n'):parsed;
    }
    field.label??=fieldname;field.fieldtype??='Data';
    if(field.fieldtype==='Select'&&Array.isArray(field.default)&&field.default.length===1)field.default=field.default[0];
    if(['on_change','get_data','get_query'].some(key=>props.has(key)))requires_adapter=true;
    fields.set(fieldname,field);
  };
  walk(ast,node=>{
    if(node.type==='ObjectProperty'&&name(node.key)==='filters'){
      const array=resolveArray(node.value);
      if(array)for(const field of array.elements)readField(field);
      if(node.value.type!=='ArrayExpression'){requires_adapter=true;diagnostics.push('dynamic_filters');}
    }
    if(node.type==='CallExpression'&&node.callee.type==='MemberExpression'&&name(node.callee.property)==='push'&&name(node.callee.object).split('.').at(-1)==='filters'){
      for(const field of node.arguments)readField(field);
      requires_adapter=true;
    }
    if(node.type==='ObjectProperty'&&['onload','after_datatable_render'].includes(name(node.key)))requires_adapter=true;
  });
  return {fields:[...fields.values()],requires_adapter,diagnostics:[...new Set(diagnostics)]};
}
