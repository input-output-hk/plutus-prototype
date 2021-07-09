#include "HsNet.h"
#include <string.h>

#ifdef _WIN32

LPWSACMSGHDR cmsg_firsthdr(LPWSAMSG mhdr) {
  return (WSA_CMSG_FIRSTHDR(mhdr));
}

LPWSACMSGHDR cmsg_nxthdr(LPWSAMSG mhdr, LPWSACMSGHDR cmsg) {
  return (WSA_CMSG_NXTHDR(mhdr, cmsg));
}

unsigned char *cmsg_data(LPWSACMSGHDR cmsg) {
  return (WSA_CMSG_DATA(cmsg));
}

unsigned int cmsg_space(unsigned int l) {
  return (WSA_CMSG_SPACE(l));
}

unsigned int cmsg_len(unsigned int l) {
  return (WSA_CMSG_LEN(l));
}

static LPFN_WSASENDMSG ptr_SendMsg;
static LPFN_WSARECVMSG ptr_RecvMsg;
/* GUIDS to lookup WSASend/RecvMsg */
static GUID WSARecvMsgGUID = WSAID_WSARECVMSG;
static GUID WSASendMsgGUID = WSAID_WSASENDMSG;

int WINAPI
WSASendMsg (SOCKET s, LPWSAMSG lpMsg, DWORD flags,
            LPDWORD lpdwNumberOfBytesRecvd, LPWSAOVERLAPPED lpOverlapped,
            LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine) {

  if (!ptr_SendMsg) {
    DWORD len;
    if (WSAIoctl(s, SIO_GET_EXTENSION_FUNCTION_POINTER,
        &WSASendMsgGUID, sizeof(WSASendMsgGUID), &ptr_SendMsg,
        sizeof(ptr_SendMsg), &len, NULL, NULL) != 0)
      return -1;
  }

  return ptr_SendMsg (s, lpMsg, flags, lpdwNumberOfBytesRecvd, lpOverlapped,
                      lpCompletionRoutine);
}

/**
 * WSARecvMsg function
 */
int WINAPI
WSARecvMsg (SOCKET s, LPWSAMSG lpMsg, LPDWORD lpdwNumberOfBytesRecvd,
            LPWSAOVERLAPPED lpOverlapped,
            LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine) {

  if (!ptr_RecvMsg) {
    DWORD len;
    if (WSAIoctl(s, SIO_GET_EXTENSION_FUNCTION_POINTER,
        &WSARecvMsgGUID, sizeof(WSARecvMsgGUID), &ptr_RecvMsg,
        sizeof(ptr_RecvMsg), &len, NULL, NULL) != 0)
      return -1;
  }

  int res = ptr_RecvMsg (s, lpMsg, lpdwNumberOfBytesRecvd, lpOverlapped,
                         lpCompletionRoutine);

  /*  If the msg was truncated then this pointer can be garbage.  */
  if (res == SOCKET_ERROR && GetLastError () == WSAEMSGSIZE)
     {
        lpMsg->Control.len = 0;
        lpMsg->Control.buf = NULL;
     }

  return res;
}
#else
struct cmsghdr *cmsg_firsthdr(struct msghdr *mhdr) {
  return (CMSG_FIRSTHDR(mhdr));
}

struct cmsghdr *cmsg_nxthdr(struct msghdr *mhdr, struct cmsghdr *cmsg) {
  return (CMSG_NXTHDR(mhdr, cmsg));
}

unsigned char *cmsg_data(struct cmsghdr *cmsg) {
  return (CMSG_DATA(cmsg));
}

int cmsg_space(int l) {
  return (CMSG_SPACE(l));
}

int cmsg_len(int l) {
  return (CMSG_LEN(l));
}
#endif /* _WIN32 */
