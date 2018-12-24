title <- "Fib (time)"

recdata <- read.table("recursive-times-Fib", header=T)
cpsdata <- read.table("cps-times-Fib", header=T)
origdata <- read.table("orig-times-Fib", header=T)

# Cut the data off at 20 so that we can see what's going on at the lower end
cpsdata    <- cpsdata[1:25,]
recdata    <- recdata[1:25,]
origdata   <- origdata[1:25,]

all <-  c(recdata$usr+recdata$sys, cpsdata$usr+cpsdata$sys, origdata$usr+origdata$sys)
ylim <- c(min(all), max(all))

start <- function(fr,col) {
    plot  (fr$n,fr$usr+fr$sys, col=col, pch=20, main=title, xlab = "n", ylab ="Time (s)", ylim=ylim)
    lines (fr$n,fr$usr+fr$sys, col=col, pch=20)
}


draw <- function(fr,col) {
    points (fr$n,fr$usr+fr$sys, col=col, pch=20)
    lines  (fr$n,fr$usr+fr$sys, col=col, pch=20)
}

mastercol="gold"
reccol="darkolivegreen3"
cpscol="blue"
origcol="darkmagenta"


start (cpsdata, cpscol)
draw  (recdata,reccol)
draw  (origdata, origcol)
    
legend(x="topleft", inset=.05, legend=c("recursive", "CPS", "Original CEK machine"), col=c(reccol, cpscol, origcol), lty=1, lw=2)
