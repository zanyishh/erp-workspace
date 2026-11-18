"""Read-only pinned-image ELF imports and literal dynamic-lookup review."""
import hashlib,json,os,stat,struct,sys,time
from pathlib import Path

TARGET=sys.argv[1].encode()
ROOTS=['/usr','/opt','/home','/etc']
started=time.monotonic();seen=set();rows=[];errors=[];files=elf_count=0;total_bytes=0

def elf(path):
    with path.open('rb') as f:
        header=f.read(64)
        if header[:4]!=b'\x7fELF':return None
        if header[:6]!=b'\x7fELF\x02\x01':raise ValueError('Unsupported ELF class/endianness')
        shoff=struct.unpack_from('<Q',header,40)[0];size,count=struct.unpack_from('<HH',header,58)
        if not shoff or not count:return {'dynamic_metadata':'absent','imports':[],'definitions':[],'needed':[]}
        if size!=64 or count>4096:raise ValueError('Unsupported ELF section layout')
        f.seek(shoff);sections=[struct.unpack('<IIQQQQIIQQ',f.read(64)) for _ in range(count)]
        result={'dynamic_metadata':'present','imports':[],'definitions':[],'needed':[]}
        for sec in sections:
            if sec[1] not in (6,11):continue
            strings=sections[sec[6]]
            if strings[5]>8*1024**2:raise ValueError('String table exceeds bounded read budget')
            f.seek(strings[4]);table=f.read(strings[5])
            def string(n):return table[n:table.index(b'\0',n)].decode('ascii')
            expected=24 if sec[1]==11 else 16
            if sec[9]!=expected or sec[5]%expected:raise ValueError('Unsupported ELF dynamic entry layout')
            f.seek(sec[4])
            for _ in range(sec[5]//expected):
                if sec[1]==6:
                    tag,value=struct.unpack('<qQ',f.read(16))
                    if tag==1:result['needed'].append(string(value))
                else:
                    name,info,other,index,value,length=struct.unpack('<IBBHQQ',f.read(24));name=string(name)
                    if name.startswith('gss_') or name in ('dlsym','dlvsym','__libc_dlsym'):
                        result['definitions' if index else 'imports'].append(name)
        return result

for root in ROOTS:
    for parent,dirs,names in os.walk(root,followlinks=False):
        dirs.sort()
        for name in sorted(names):
            if time.monotonic()-started>240:raise TimeoutError('Read-only inventory exceeded 240-second budget')
            path=Path(parent)/name
            try:
                st=path.lstat();identity=(st.st_dev,st.st_ino)
                if not stat.S_ISREG(st.st_mode) or identity in seen:continue
                seen.add(identity);files+=1;total_bytes+=st.st_size;literal=False;digest=hashlib.sha256()
                with path.open('rb') as f:
                    tail=b''
                    while chunk:=f.read(65536):
                        digest.update(chunk)
                        if TARGET in tail+chunk:literal=True
                        tail=chunk[-len(TARGET):]
                data=elf(path)
                if data is not None:elf_count+=1
                if literal or (data and (data['imports'] or 'libgssapi_krb5.so.2' in data['needed'])):
                    rows.append({'path':str(path),'bytes':st.st_size,'sha256':digest.hexdigest(),'target_literal':literal,'elf':data})
            except (OSError,ValueError,struct.error) as error:
                errors.append({'path':str(path),'error':str(error)})
print(json.dumps({'status':'completed','roots':ROOTS,'target':TARGET.decode(),'regular_files':files,'elf_files':elf_count,'bytes_read':total_bytes,'seconds':time.monotonic()-started,'matches':rows,'errors':errors,'limits':'Installed regular files only. Literal strings and ELF imports do not exclude runtime-generated dlsym names, downloaded code, absent plugins, or external files.'},indent=2))
