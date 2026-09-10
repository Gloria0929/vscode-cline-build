import { SVGProps } from "react"
import type { Environment } from "../../../src/shared/config-types"
import chatLogoSvg from "./chat-logo.svg"

const LOGO_NAME = (props: SVGProps<SVGSVGElement> & { environment?: Environment }) => {
	const { className, style, width, height } = props
	return <img src={chatLogoSvg} alt="AI Coder" className={className} style={style} width={width} height={height} />
}
export default LOGO_NAME
