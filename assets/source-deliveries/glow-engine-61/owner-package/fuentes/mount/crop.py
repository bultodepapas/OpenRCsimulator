import cv2, sys
im=cv2.imread("ref/amazon_mount.jpg")
def crop(name,x0,y0,x1,y1,S=3,step=10):
    c=cv2.resize(im[y0:y1,x0:x1],None,fx=S,fy=S,interpolation=cv2.INTER_CUBIC)
    for x in range((x0//step+1)*step,x1,step):
        X=int((x-x0)*S); col=(0,0,255) if x%50==0 else (255,200,0)
        cv2.line(c,(X,0),(X,c.shape[0]),col,1)
        if x%50==0: cv2.putText(c,str(x),(X+2,12),cv2.FONT_HERSHEY_SIMPLEX,0.4,(0,0,255),1)
    for y in range((y0//step+1)*step,y1,step):
        Y=int((y-y0)*S); col=(0,0,255) if y%50==0 else (255,200,0)
        cv2.line(c,(0,Y),(c.shape[1],Y),col,1)
        if y%50==0: cv2.putText(c,str(y),(2,Y-2),cv2.FONT_HERSHEY_SIMPLEX,0.4,(0,0,255),1)
    cv2.imwrite(f"ref/crop_{name}.jpg",c)
a=sys.argv[1:]
crop(a[0],*map(int,a[1:5]),S=float(a[5]) if len(a)>5 else 3)
