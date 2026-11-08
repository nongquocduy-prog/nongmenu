import sys,zipfile,os
if len(sys.argv)!=4:
 print('Usage: python3 insert_trace.py input.ipa Ongnongios1.dylib output.ipa'); sys.exit(2)
src,dylib,dst=sys.argv[1:]
member='Payload/CoinMaster.app/Ongnongios1.dylib'
with zipfile.ZipFile(src) as inp, zipfile.ZipFile(dst,'w') as out:
 for item in inp.infolist():
  if item.filename==member or item.filename.startswith('Payload/CoinMaster.app/_CodeSignature/'):
   continue
  out.writestr(item,inp.read(item.filename))
 out.write(dylib,member,compress_type=zipfile.ZIP_STORED)
with zipfile.ZipFile(dst) as z:
 assert z.testzip() is None
 print('Created unsigned IPA:',dst,'size',os.path.getsize(dst))
print('Re-sign entire IPA in ESign before installing. Original signature is invalidated.')
