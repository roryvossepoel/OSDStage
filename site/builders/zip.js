/* Small ZIP writer (stored entries, UTF-8). No network or third-party runtime. */
const BuilderZip=(()=>{
 const enc=new TextEncoder();
 function crc32(bytes){let crc=0xffffffff;for(const b of bytes){crc^=b;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;}
 function header(size){const bytes=new Uint8Array(size),v=new DataView(bytes.buffer);return {bytes,u16:(at,n)=>v.setUint16(at,n,true),u32:(at,n)=>v.setUint32(at,n,true)}}
 function create(files){const parts=[],central=[];let offset=0,centralLength=0;for(const [path,text]of Object.entries(files)){
  const name=enc.encode(path),data=enc.encode(text),crc=crc32(data),h=header(30);h.u32(0,0x04034b50);h.u16(4,20);h.u16(6,0x800);h.u16(12,0x5821);h.u32(14,crc);h.u32(18,data.length);h.u32(22,data.length);h.u16(26,name.length);parts.push(h.bytes,name,data);
  const c=header(46);c.u32(0,0x02014b50);c.u16(4,20);c.u16(6,20);c.u16(8,0x800);c.u16(14,0x5821);c.u32(16,crc);c.u32(20,data.length);c.u32(24,data.length);c.u16(28,name.length);c.u32(42,offset);central.push(c.bytes,name);centralLength+=46+name.length;offset+=30+name.length+data.length;
 }const end=header(22);end.u32(0,0x06054b50);end.u16(8,central.length/2);end.u16(10,central.length/2);end.u32(12,centralLength);end.u32(16,offset);const chunks=[...parts,...central,end.bytes],out=new Uint8Array(offset+centralLength+22);let pos=0;for(const c of chunks){out.set(c,pos);pos+=c.length}return out;}
 return {create};
})();if(typeof module!=='undefined'&&module.exports)module.exports=BuilderZip;
