"""Merge local launch identities without replacing another workspace's credentials."""
import copy


def upgrade(value):
    if value.get('version')==2:
        result=copy.deepcopy(value)
        if not isinstance(result.get('workspaces'),list):raise ValueError('Invalid local profiles.')
        ids=[row.get('id') for row in result['workspaces']]
        if not all(isinstance(key,str) and key for key in ids) or len(set(ids))!=len(ids):raise ValueError('Duplicate local profile identities.')
        return result
    workspaces=value.get('workspaces')
    if not isinstance(workspaces,list):raise ValueError('Existing local workspace settings are unsupported; preserve them.')
    rows=[]
    for row in workspaces:
        industry=row.get('industry')
        if industry not in ('general','knitting') or row.get('site')!='native-test.localhost':
            raise ValueError('Unexpected legacy local workspace; preserve it.')
        rows.append({**{key:row[key] for key in ('site','company','account','key','secret')},
            'id':'demo-'+industry,'label':'General ERP demo' if industry=='general' else 'Knitting demo',
            'origin':'http://127.0.0.1:8081'})
    return {'version':2,'selected_workspace':'demo-general','workspaces':rows}


def merge(existing, additions, *, select=None):
    result=upgrade(existing)
    rows={row['id']:row for row in result['workspaces']}
    for row in additions:
        if not row.get('id'):raise ValueError('A local profile identity is required.')
        previous=rows.get(row['id'])
        if previous and any(previous.get(key)!=row.get(key) for key in ('origin','site','account')):
            raise ValueError('A local profile identity already belongs to another workspace.')
        rows[row['id']]=copy.deepcopy(row)
    result['workspaces']=list(rows.values())
    result['selected_workspace']=select or result.get('selected_workspace')
    if result['selected_workspace'] not in rows:raise ValueError('The selected workspace does not exist.')
    return result
