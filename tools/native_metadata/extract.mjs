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
  if(node.type==='MemberExpression' && node.computed && node.property.type==='NumericLiteral' &&
     node.object.type==='CallExpression' && name(node.object.callee)==='erpnext.utils.get_fiscal_year'){
    const [date,withDates]=node.object.arguments.map(value);
    const kind=['fiscal_year','fiscal_start','fiscal_end'][node.property.value];
    if(kind && date?.native_default==='today' && withDates===true && node.object.arguments.length===2)
      return {native_default:kind};
  }
  if(node.type==='LogicalExpression' && node.operator==='||'){
    const first=value(node.left), second=value(node.right);
    if(first?.native_default==='user' && ['fiscal_start','fiscal_end'].includes(second?.native_default))
      return {native_default:'fallback',first,second};
  }
  if(node.type==='ConditionalExpression' && node.alternate.type==='StringLiteral' && node.alternate.value===''){
    const companyDefault=n=>n?.type==='CallExpression' && name(n.callee)==='frappe.defaults.get_user_default' &&
      n.arguments.length===1 && n.arguments[0].value==='Company';
    const bank=node.consequent;
    if(companyDefault(node.test) && bank.type==='MemberExpression' && name(bank.property)==='default_bank_account' &&
       bank.object.type==='MemberExpression' && companyDefault(bank.object.property) &&
       name(bank.object.object)==='locals.:Company') return {native_default:'bank_account'};
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
    if(callee==='frappe.defaults.get_global_default' && ['year_start_date','year_end_date'].includes(args[0]))
      return {native_default:'global_date',key:args[0]};
    if(callee==='frappe.datetime.now_datetime' && !args.length) return {native_default:'user_datetime'};
    if(callee==='frappe.datetime.convert_to_system_tz' && node.arguments.length===1){
      const offset=node.arguments[0];
      if(offset.type==='CallExpression' && name(offset.callee)==='frappe.datetime.add_months' &&
          offset.arguments.length===2 && value(offset.arguments[0])?.native_default==='user_datetime' &&
          Number.isInteger(value(offset.arguments[1]))) return {native_default:'system_month_offset',value:value(offset.arguments[1])};
    }
    if(['frappe.datetime.get_today','frappe.datetime.nowdate','frappe.datetime.now_date'].includes(callee)&&!args.length)
      return {native_default:'today'};
    if(callee==='erpnext.utils.get_fiscal_year' && (!args.length || args[0]?.native_default==='today') && !args[1])return {native_default:'fiscal_year'};
    if(['frappe.datetime.month_start','frappe.datetime.month_end','frappe.datetime.year_start','frappe.datetime.year_end'].includes(callee))return {native_default:callee.split('.').at(-1)};
    if(['frappe.datetime.add_months','frappe.datetime.add_days'].includes(callee)&&['today','month_start'].includes(args[0]?.native_default)&&Number.isInteger(args[1]))
      return {native_default:'date_offset',unit:callee.endsWith('months')?'months':'days',value:args[1],
        ...(args[0].native_default==='month_start'?{base:'month_start'}:{})};
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

export function extractReportFilters(source, reportName) {
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
      if(key==='options' && property.value?.type==='CallExpression' && !property.value.arguments.length){
        const fn=name(property.value.callee);
        const optionSource={
          ...(reportName==='Dimension-wise Accounts Balance Report'?{'get_accounting_dimension_options':'accounting_dimensions'}:{}),
          ...(new Set(['Accounts Receivable','Accounts Receivable Summary','Accounts Payable','Accounts Payable Summary']).has(reportName)
            ?{'get_party_type_options':'party_types'}:{}),
          'erpnext.get_presentation_currency_list':'enabled_currencies',
          'erpnext.financial_statements.get_accounting_dimension_options':'enabled_accounting_dimensions',
        }[fn];
        if(optionSource){field.native_options=optionSource;continue;}
      }
      if(key==='options' && reportName==='General Ledger' && fieldname==='party_type' &&
          property.value?.type==='CallExpression' && name(property.value.callee)==='Object.keys' &&
          property.value.arguments.length===1 && name(property.value.arguments[0])==='frappe.boot.party_account_types'){
        field.native_options='party_types';continue;
      }
      const parsed=value(property.value);
      if(parsed===unresolved){requires_adapter=true;diagnostics.push(`${fieldname}.${key}`);if(key==='options')field.dynamic_options=true;continue;}
      field[key]=key==='options'&&Array.isArray(parsed)?parsed.map(v=>typeof v==='object'?v.value:v).join('\n'):parsed;
    }
    field.label??=fieldname;field.fieldtype??='Data';
    if(field.fieldtype==='Select'&&Array.isArray(field.default)&&field.default.length===1)field.default=field.default[0];
    if(['on_change','get_data','get_query'].some(key=>props.has(key)))requires_adapter=true;
    fields.set(fieldname,field);
  };
  const libraries=new Map();
  const knownLibraries=new Set(['erpnext.financial_statements','erpnext.sales_trends_filters','erpnext.purchase_trends_filters']);
  const reportRoot=node=>node?.type==='MemberExpression' && name(node.object)==='frappe.query_reports';
  let registration;
  const unresolvedFilters=()=>{requires_adapter=true;diagnostics.push('dynamic_filters');};
  function readArray(node){
    const array=resolveArray(node);
    if(!array){unresolvedFilters();return;}
    // A local function may modify defaults/options or conditionally append fields after its declaration.
    if(node.type!=='ArrayExpression') unresolvedFilters();
    for(const item of array.elements){
      if(item?.type==='SpreadElement' && item.argument.type==='MemberExpression' && name(item.argument.property)==='filters'){
        const inherited=libraries.get(name(item.argument.object));
        if(inherited){readArray(inherited);continue;}
      }
      readField(item);
    }
  }
  function readConfiguration(node){
    if(node?.type==='ObjectExpression'){
      for(const property of node.properties){
        const key=name(property.key);
        if(key==='filters') readArray(property.value);
        if(['onload','after_datatable_render','formatter','get_datatable_options'].includes(key)) requires_adapter=true;
      }
    } else if(node?.type==='CallExpression' && name(node.callee)==='$.extend'){
      for(const arg of node.arguments){
        if(arg.type==='ObjectExpression') readConfiguration(arg);
        else if(libraries.has(name(arg))) readArray(libraries.get(name(arg)));
        else unresolvedFilters();
      }
    } else unresolvedFilters();
  }
  for(const statement of ast.program.body){
    const expr=statement.expression;
    if(!expr) continue;
    if(expr.type==='AssignmentExpression' && expr.operator==='='){
      if(knownLibraries.has(name(expr.left)) && expr.right.type==='ObjectExpression'){
        const own=expr.right.properties.find(p=>name(p.key)==='filters');
        if(own) libraries.set(name(expr.left),own.value);
      }
      if(reportRoot(expr.left)){
        registration=name(expr.left);
        readConfiguration(expr.right);
      }
    }
    if(expr.type!=='CallExpression' || expr.callee.type!=='MemberExpression') continue;
    if(name(expr.callee)==='erpnext.utils.add_dimensions') requires_adapter=true;
    const target=expr.callee.object;
    if(!reportRoot(target.object) || name(target.object)!==registration || name(target.property)!=='filters') continue;
    const method=name(expr.callee.property);
    if(method==='push') for(const item of expr.arguments) readField(item);
    else if(method==='splice' && expr.arguments.length===2 && expr.arguments.every(a=>a.type==='NumericLiteral'&&Number.isInteger(a.value)&&a.value>=0)){
      const [start,count]=expr.arguments.map(a=>a.value);
      for(const key of [...fields.keys()].slice(start,start+count)) fields.delete(key);
    } else unresolvedFilters();
  }
  if(!registration) unresolvedFilters();
  return {fields:[...fields.values()],requires_adapter,diagnostics:[...new Set(diagnostics)]};
}
