/* Stand-ins for desktop-only functions Mesa's Dozen driver imports (Win32 WSI over GDI,
 * the shader disk cache path and the DXIL.dll version query). Defining them here keeps
 * user32, gdi32, shell32 and version.dll out of vulkan_dzn.dll's import table. */

typedef unsigned long long u64;

#define UWP_STUB(name, value) \
	u64 name(void) { return (u64)(value); } \
	void* __imp_##name = (void*)&name;

/* GetClientRect NO puede ser un stub que devuelva cero.
 *
 * El WSI de Windows de Mesa mide la ventana con esta llamada y, si falla, da la superficie
 * por perdida:
 *
 *     if (!GetClientRect(surface->hwnd, &win_rect))
 *        return VK_ERROR_SURFACE_LOST_KHR;          // wsi_common_win32.cpp
 *
 * En una Xbox no hay ventanas Win32 que medir: lo que hay es una CoreWindow, y quien la
 * conoce es el ejecutable. Asi que se le pregunta a el, por dos funciones que exporta —
 * `uwp_get_width` y `uwp_get_height` —, y se contesta que si. Sin esto, `hwnd` da igual lo
 * que valga (un puntero a la CoreWindow, un 1): la primera consulta de capacidades falla y
 * no hay imagen.
 *
 * Es la misma pieza que usa el port de Monster Hunter Portable 3rd, que ya juega en esta
 * consola con Dozen. */

typedef struct { long left, top, right, bottom; } uwp_rect;
typedef unsigned int (*uwp_size_fn)(void);

/* De kernel32, que si esta en el contenedor. Se declaran a mano para no arrastrar windows.h. */
void* __stdcall GetModuleHandleW(const unsigned short* name);
void* __stdcall GetProcAddress(void* module, const char* name);

static uwp_size_fn uwp_width_fn;
static uwp_size_fn uwp_height_fn;
static int uwp_buscadas;

static void uwp_buscar_tamano(void)
{
	void* exe;
	if (uwp_buscadas)
		return;
	uwp_buscadas = 1;
	exe = GetModuleHandleW(0);
	if (exe == 0)
		return;
	uwp_width_fn = (uwp_size_fn)GetProcAddress(exe, "uwp_get_width");
	uwp_height_fn = (uwp_size_fn)GetProcAddress(exe, "uwp_get_height");
}

int __stdcall GetClientRect(void* hwnd, uwp_rect* rect)
{
	(void)hwnd;
	if (rect == 0)
		return 0;
	uwp_buscar_tamano();
	rect->left = 0;
	rect->top = 0;
	rect->right = uwp_width_fn ? (long)uwp_width_fn() : 1920;
	rect->bottom = uwp_height_fn ? (long)uwp_height_fn() : 1080;
	return 1;
}
void* __imp_GetClientRect = (void*)&GetClientRect;

UWP_STUB(GetDC, 0)
UWP_STUB(CreateCompatibleDC, 0)
UWP_STUB(CreateDIBSection, 0)
UWP_STUB(DeleteDC, 0)
UWP_STUB(DeleteObject, 0)
UWP_STUB(GetObjectA, 0)
UWP_STUB(SelectObject, 0)
UWP_STUB(StretchBlt, 0)
UWP_STUB(SHGetFolderPathA, 0x80004005) /* E_FAIL: no disk cache directory */
UWP_STUB(GetFileVersionInfoSizeW, 0)
UWP_STUB(GetFileVersionInfoW, 0)
UWP_STUB(VerQueryValueW, 0)
