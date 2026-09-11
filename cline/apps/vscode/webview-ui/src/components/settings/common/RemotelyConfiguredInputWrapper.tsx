import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

export function RemotelyConfiguredInputWrapper({ hidden, children }: React.PropsWithChildren<{ hidden: boolean }>) {
	return (
		<Tooltip>
			<TooltipContent hidden={hidden}>此设置由您组织的远程配置管理</TooltipContent>
			{/*
			 * TooltipTrigger renders a shrink-to-fit <button>, so without these the
			 * wrapped field collapses to its intrinsic width and a sibling field ends
			 * up beside it on the same row. Force a full-width block so each field
			 * gets its own row (LiteLLM's 接口地址/API 密钥, Vertex, Anthropic, ...).
			 */}
			<TooltipTrigger className="block w-full">{children}</TooltipTrigger>
		</Tooltip>
	)
}

export const LockIcon = () => <i className="codicon codicon-lock text-description text-sm" />
