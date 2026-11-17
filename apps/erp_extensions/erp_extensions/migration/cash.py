"""Source shared-category totals; not inferred company cash/bank GL balances."""
from decimal import Decimal, InvalidOperation
from .contracts import canonical


def amount(value):
    try:result=Decimal(str(value))
    except (InvalidOperation,TypeError,ValueError):raise ValueError('An exact cash control amount is required.')
    if not result.is_finite():raise ValueError('An exact cash control amount is required.')
    return result


def summarize(records,controls):
    groups={}
    for control in controls:
        key=control['cash_book_id']
        if key in groups:raise ValueError('Duplicate shared cash control identity.')
        groups[key]={'cash_book_id':key,'label':control['label'],'opening_debit':Decimal(0),'opening_credit':Decimal(0),
            'movement_debit':Decimal(0),'movement_credit':Decimal(0),'opening_count':0,'movement_count':0}
    if not controls:return []
    seen={}
    for record in records:
        key=record['source_key'];digest=canonical(record)
        if key in seen:
            if seen[key]!=digest:raise ValueError('Conflicting shared cash source identity.')
            continue
        seen[key]=digest;fields=record['business_data']['fields'];book=fields.get('cash_book')
        if book not in groups:raise ValueError('A shared cash row has no verified category control.')
        if record['family'] not in ('cash_opening','cash_movement'):raise ValueError('Only shared cash originals enter these controls.')
        prefix='opening' if record['family']=='cash_opening' else 'movement';group=groups[book]
        group[prefix+'_debit']+=amount(fields.get('debit'));group[prefix+'_credit']+=amount(fields.get('credit'))
        group[prefix+'_count']+=1
    result=[]
    for control in controls:
        group=groups[control['cash_book_id']]
        net=group['opening_debit']-group['opening_credit']+group['movement_debit']-group['movement_credit']
        verified=all(group[k]==amount(control[k]) for k in ('opening_debit','opening_credit','movement_debit','movement_credit'))
        verified=verified and all(group[k]==control[k] for k in ('opening_count','movement_count')) and net==amount(control['closing_net'])
        result.append({**{k:format(v,'f') if isinstance(v,Decimal) else v for k,v in group.items()},
            'opening_net':format(group['opening_debit']-group['opening_credit'],'f'),
            'movement_net':format(group['movement_debit']-group['movement_credit'],'f'),
            'net':format(net,'f'),'expected_net':str(control['closing_net']),'verified':verified,
            'basis':'Original shared cash ledger projection','as_of_date':control.get('as_of_date')})
    return result
