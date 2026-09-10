import { ModelInfo, openAiModelInfoSafeDefaults } from "@shared/api"
import { Mode } from "@shared/storage/types"
import { VSCodeButton, VSCodeLink } from "@vscode/webview-ui-toolkit/react"
import { RefreshCwIcon } from "lucide-react"
import { useExtensionState } from "@/context/ExtensionStateContext"
import { useProviderConfig } from "@/hooks/useProviderConfig"
import { useProviderModelSelection } from "@/hooks/useProviderModelSelection"
import { useProviderModels } from "@/hooks/useProviderModels"
import { DebouncedTextField } from "../common/DebouncedTextField"
import { ModelAutocomplete } from "../common/ModelAutocomplete"
import { ModelInfoView } from "../common/ModelInfoView"
import { LockIcon, RemotelyConfiguredInputWrapper } from "../common/RemotelyConfiguredInputWrapper"
import ReasoningEffortSelector from "../ReasoningEffortSelector"
import { useProviderApiKeyField } from "../utils/useProviderApiKeyField"

const LITELLM_PROVIDER_ID = "litellm"

function customModelInfo(modelId: string): ModelInfo {
	return {
		...openAiModelInfoSafeDefaults,
		name: modelId,
	}
}

/**
 * Props for the LiteLlmProvider component
 */
interface LiteLlmProviderProps {
	showModelOptions: boolean
	isPopup?: boolean
	currentMode: Mode
}

export const LiteLlmProvider = ({ showModelOptions, isPopup, currentMode }: LiteLlmProviderProps) => {
	const { remoteConfigSettings } = useExtensionState()
	const { models, defaultModelId, isLoading, isStale, error, refresh } = useProviderModels(LITELLM_PROVIDER_ID)
	const { config, write, commitSelection } = useProviderConfig(LITELLM_PROVIDER_ID)
	const { selectedModelId, selectedModelInfo, commitModelSelection } = useProviderModelSelection(
		LITELLM_PROVIDER_ID,
		currentMode,
		{
			models,
			defaultModelId,
			config,
			commitSelection,
			customModelInfo,
		},
	)
	const { savedApiKeyMask, handleApiKeyChange } = useProviderApiKeyField({
		apiKeyLength: config?.apiKeyLength,
		providerName: "LiteLLM",
		write,
	})

	const handleModelChange = (newModelId: string, modelInfo: ModelInfo | undefined) => {
		void commitModelSelection({
			modelId: newModelId,
			modelInfo: modelInfo ?? customModelInfo(newModelId),
		}).catch((err) => console.error("Failed to commit LiteLLM model selection:", err))
	}

	const onRefreshModels = async () => {
		await refresh()
	}

	// Writes are safe before the initial config read resolves: write() does not
	// depend on loaded config, and useProviderConfig drops the stale read
	// response. Gating on `config` here would silently discard text typed right
	// after the settings view mounts.
	const handleBaseUrlChange = (value: string) => {
		void write({ baseUrl: value }).catch((err) => console.error("Failed to update LiteLLM base URL:", err))
	}

	return (
		<div>
			<RemotelyConfiguredInputWrapper hidden={remoteConfigSettings?.liteLlmBaseUrl === undefined}>
				<DebouncedTextField
					disabled={remoteConfigSettings?.liteLlmBaseUrl !== undefined}
					initialValue={config?.baseUrl || ""}
					onChange={handleBaseUrlChange}
					placeholder={"默认：http://localhost:4000"}
					style={{ width: "100%" }}
					type="text">
					<div className="flex items-center gap-2 mb-1">
						<span style={{ fontWeight: 500 }}>接口地址（可选）</span>
						{remoteConfigSettings?.liteLlmBaseUrl !== undefined && <LockIcon />}
					</div>
				</DebouncedTextField>
			</RemotelyConfiguredInputWrapper>
			<RemotelyConfiguredInputWrapper hidden={!remoteConfigSettings?.configuredApiKeys?.litellm}>
				<DebouncedTextField
					disabled={remoteConfigSettings?.configuredApiKeys?.litellm}
					initialValue={savedApiKeyMask}
					onChange={handleApiKeyChange}
					placeholder="默认：noop"
					style={{ width: "100%" }}
					type="password">
					<div className="flex items-center gap-2 mb-1">
						<span style={{ fontWeight: 500 }}>API 密钥</span>
						{remoteConfigSettings?.configuredApiKeys?.litellm && <LockIcon />}
					</div>
				</DebouncedTextField>
			</RemotelyConfiguredInputWrapper>
			{showModelOptions && (
				<>
					{isStale && <div role="status">对于当前 LiteLLM 配置，模型列表可能不是最新。</div>}
					{error && <div role="alert">{error}</div>}
					<ModelAutocomplete
						label="模型"
						models={models}
						onChange={handleModelChange}
						placeholder="搜索或输入自定义模型 ID..."
						selectedModelId={selectedModelId}
					/>
					<VSCodeButton
						className={`my-2 ${isLoading ? "animate-pulse" : ""}`}
						disabled={isLoading}
						onClick={onRefreshModels}>
						{isLoading ? (
							"加载中..."
						) : (
							<>
								刷新模型 <RefreshCwIcon className="ml-1" />
							</>
						)}
					</VSCodeButton>

					{selectedModelInfo?.supportsReasoning && (
						<ReasoningEffortSelector
							currentMode={currentMode}
							defaultEffort="none"
							description="选择“无”可禁用深度思考。力度越大越深入，但消耗更多 Token。"
							onEffortChange={(effort) => {
								void write({
									reasoning: { enabled: effort !== "none", effort: effort !== "none" ? effort : undefined },
								}).catch((err) => console.error("Failed to update LiteLLM reasoning effort:", err))
							}}
						/>
					)}

					<ModelInfoView isPopup={isPopup} modelInfo={selectedModelInfo} selectedModelId={selectedModelId} />
				</>
			)}
			<p
				style={{
					fontSize: "12px",
					marginTop: "5px",
					color: "var(--vscode-descriptionForeground)",
				}}>
				深度思考适用于 Sonnet-4、o3-mini、Deepseek R1 等模型。更多信息请参阅{" "}
					<VSCodeLink
						href="https://docs.litellm.ai/docs/reasoning_content"
						style={{ display: "inline", fontSize: "inherit" }}>
						深度思考模式配置
					</VSCodeLink>
			</p>

			<p
				style={{
					fontSize: "12px",
					marginTop: "5px",
					color: "var(--vscode-descriptionForeground)",
				}}>
				LiteLLM 提供统一接口访问各 LLM 提供商的模型。请参阅其{" "}
					<VSCodeLink href="https://docs.litellm.ai/docs/" style={{ display: "inline", fontSize: "inherit" }}>
						快速入门指南
					</VSCodeLink>{" "}
					以了解更多信息。
			</p>
		</div>
	)
}
