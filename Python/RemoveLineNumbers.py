import re
import time
FILE_PATH = 'Test.txt'  #  Give file name here

# Place Code in same folder as the file

def startregex():
   print 'Start'
   name = str(int(time.time()))+'.txt'
   fw = open(name,'w')
   with open(FILE_PATH,'r') as f:
       for line in f:
           m = re.sub('^(\s*)(\d*)(\s*)','',line)
           fw.write(m)
   f.closed
   fw.close()

if __name__ == '__main__':
   startregex()
